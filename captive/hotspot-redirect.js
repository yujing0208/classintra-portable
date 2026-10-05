/**
 * Hotspot HTTPS Redirect Service
 *
 * Features:
 *   1. DNS server (UDP 53) — intercepts spark.changyan.com -> hotspot host IP
 *   2. HTTPS reverse proxy (TCP 443) — TLS termination -> localhost:9001
 *
 * Requires Administrator privileges (bind ports 53 and 443)
 */

'use strict';

const dgram = require('dgram');
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

// ============================================================
// Config
// ============================================================
const CONFIG = {
  // 支持多个域名拦截
  interceptDomains: ['spark.changyan.com', 'ai.changyan.com'],
  hotspotIP: '192.168.137.1',
  dnsPort: 53,
  httpsPort: 443,
  upstreamDNS: '223.5.5.5',
  targetHost: 'localhost',
  targetPort: 9001,
  certDir: path.join(__dirname, 'certs'),
};

const CERT_PATH = path.join(CONFIG.certDir, 'cert.pem');
const KEY_PATH = path.join(CONFIG.certDir, 'key.pem');

// ============================================================
// DNS packet utilities
// ============================================================

/**
 * Parse domain name from DNS query packet
 */
function parseDNSName(buf, offset) {
  const labels = [];
  let jumped = false;
  let jumpOffset = offset;
  let pos = offset;

  while (buf[pos] !== 0) {
    // Check for compression pointer
    if ((buf[pos] & 0xC0) === 0xC0) {
      const pointer = ((buf[pos] & 0x3F) << 8) | buf[pos + 1];
      if (!jumped) {
        jumpOffset = pos + 2;
      }
      pos = pointer;
      jumped = true;
    } else {
      const len = buf[pos];
      labels.push(buf.toString('utf8', pos + 1, pos + 1 + len).toLowerCase());
      pos += len + 1;
    }
  }

  if (!jumped) {
    jumpOffset = pos + 1;
  }

  return { name: labels.join('.'), offset: jumpOffset };
}

/**
 * Build DNS A-record response packet
 */
function buildDNSResponse(requestBuf, ipAddress) {
  const response = Buffer.alloc(requestBuf.length + 16);

  requestBuf.copy(response, 0, 0, requestBuf.length);

  // Flags: QR=1(response), OPCODE=0, AA=0, TC=0, RD=1
  response[2] = 0x81;
  response[3] = 0x80; // RA=1, Z=0, RCODE=0(no error)

  // Answer count = 1
  response[6] = 0x00;
  response[7] = 0x01;

  // Find end of question section
  const { offset: questionEnd } = parseDNSName(requestBuf, 12);
  const answerOffset = questionEnd + 4; // skip QTYPE(2) + QCLASS(2)

  // Build answer section
  let pos = answerOffset;
  // Name pointer to question domain (offset 12)
  response[pos++] = 0xC0;
  response[pos++] = 0x0C;

  // TYPE: A = 0x0001
  response[pos++] = 0x00;
  response[pos++] = 0x01;

  // CLASS: IN = 0x0001
  response[pos++] = 0x00;
  response[pos++] = 0x01;

  // TTL: 300 seconds
  response[pos++] = 0x00;
  response[pos++] = 0x00;
  response[pos++] = 0x01;
  response[pos++] = 0x2C;

  // RDLENGTH: 4
  response[pos++] = 0x00;
  response[pos++] = 0x04;

  // RDATA: IP address
  const octets = ipAddress.split('.').map(Number);
  response[pos++] = octets[0];
  response[pos++] = octets[1];
  response[pos++] = octets[2];
  response[pos++] = octets[3];

  return response.slice(0, pos);
}

// ============================================================
// DNS Server
// ============================================================

function createDNSServer() {
  const server = dgram.createSocket('udp4');
  const upstreamAddr = CONFIG.upstreamDNS;
  const upstreamPort = 53;

  server.on('error', (err) => {
    console.error(`[DNS] Server error: ${err.message}`);
    if (err.code === 'EADDRINUSE') {
      console.error('[DNS] Port 53 is in use. Run as Administrator first.');
    }
  });

  server.on('message', async (msg, rinfo) => {
    try {
      const { name } = parseDNSName(msg, 12);

      // 检查是否需要拦截
      const shouldIntercept = CONFIG.interceptDomains.some(domain =>
        name === domain || name.endsWith('.' + domain)
      );

      if (shouldIntercept) {
        // Intercepted - return hotspot IP
        const response = buildDNSResponse(msg, CONFIG.hotspotIP);
        server.send(response, rinfo.port, rinfo.address, (err) => {
          if (!err) {
            console.log(`[DNS] HIT  ${name} -> ${CONFIG.hotspotIP}  (from ${rinfo.address})`);
          }
        });
      } else {
        // Forward to upstream DNS
        const upstreamSocket = dgram.createSocket('udp4');
        const timeout = setTimeout(() => {
          upstreamSocket.close();
        }, 5000);

        upstreamSocket.on('message', (upMsg) => {
          clearTimeout(timeout);
          server.send(upMsg, rinfo.port, rinfo.address, (err) => {
            if (err) console.error(`[DNS] Forward response failed: ${err.message}`);
          });
          upstreamSocket.close();
        });

        upstreamSocket.on('error', (err) => {
          clearTimeout(timeout);
          upstreamSocket.close();
          console.error(`[DNS] Upstream error: ${err.message}`);
        });

        upstreamSocket.send(msg, upstreamPort, upstreamAddr, (err) => {
          if (err) {
            clearTimeout(timeout);
            upstreamSocket.close();
            console.error(`[DNS] Forward failed: ${err.message}`);
          }
        });
      }
    } catch (err) {
      // Ignore unparseable packets
    }
  });

  server.on('listening', () => {
    const addr = server.address();
    console.log(`[DNS] Listening on ${addr.address}:${addr.port}`);
    console.log(`[DNS] Intercept rules:`);
    CONFIG.interceptDomains.forEach(domain => {
      console.log(`[DNS]   *.${domain} -> ${CONFIG.hotspotIP}`);
    });
    console.log(`[DNS] Upstream: ${CONFIG.upstreamDNS}`);
  });

  return server;
}

// ============================================================
// HTTPS Reverse Proxy
// ============================================================

function createHTTPSProxy() {
  let tlsOptions;
  try {
    tlsOptions = {
      cert: fs.readFileSync(CERT_PATH),
      key: fs.readFileSync(KEY_PATH),
    };
    console.log(`[TLS] Certificate loaded: ${CERT_PATH}`);
  } catch (err) {
    console.error(`[TLS] Failed to load certificate: ${err.message}`);
    console.error('[TLS] Run cert generation first.');
    process.exit(1);
  }

  const proxy = https.createServer(tlsOptions, (clientReq, clientRes) => {
    const options = {
      hostname: CONFIG.targetHost,
      port: CONFIG.targetPort,
      path: clientReq.url,
      method: clientReq.method,
      headers: {
        ...clientReq.headers,
        'X-Forwarded-For': clientReq.socket.remoteAddress,
        'X-Forwarded-Proto': 'https',
        'X-Forwarded-Host': clientReq.headers.host || CONFIG.targetDomain,
      },
    };

    console.log(`[HTTPS] ${clientReq.method} ${clientReq.url}  (from ${clientReq.socket.remoteAddress})`);

    // Track if we've already sent a response to prevent double-send
    let responded = false;
    const respond = (statusCode, body) => {
      if (responded) return;
      responded = true;
      if (!clientRes.headersSent) {
        clientRes.writeHead(statusCode, { 'Content-Type': 'text/plain; charset=utf-8' });
      }
      clientRes.end(body);
    };

    const proxyReq = http.request(options, (proxyRes) => {
      // Forward response status and headers
      if (!responded) {
        responded = true;
        clientRes.writeHead(proxyRes.statusCode, proxyRes.headers);
      }
      // Pipe response body, with error handling
      proxyRes.on('error', (err) => {
        console.error(`[HTTPS] Response stream error: ${err.message}`);
        clientRes.destroy();
      });
      proxyRes.pipe(clientRes);
    });

    // Handle proxy request errors (ECONNREFUSED, ECONNRESET, etc.)
    proxyReq.on('error', (err) => {
      console.error(`[HTTPS] Backend unreachable: ${err.message}`);
      respond(502, `Backend service unavailable: ${err.message}`);
    });

    // Handle client errors (disconnect, timeout, etc.)
    clientReq.on('error', (err) => {
      console.error(`[HTTPS] Client request error: ${err.message}`);
      proxyReq.destroy();
    });

    clientRes.on('error', (err) => {
      console.error(`[HTTPS] Client response error: ${err.message}`);
      proxyReq.destroy();
    });

    // Pipe client request body to backend
    clientReq.pipe(proxyReq);
  });

  // WebSocket upgrade support
  proxy.on('upgrade', (clientReq, clientSocket, head) => {
    const options = {
      hostname: CONFIG.targetHost,
      port: CONFIG.targetPort,
      path: clientReq.url,
      method: clientReq.method,
      headers: {
        ...clientReq.headers,
        'X-Forwarded-For': clientReq.socket.remoteAddress,
        'X-Forwarded-Proto': 'https',
      },
    };

    console.log(`[HTTPS] WS upgrade ${clientReq.url}`);

    const proxyReq = http.request(options);
    proxyReq.on('upgrade', (proxyRes, proxySocket, proxyHead) => {
      // Handle WebSocket stream errors (most likely during backend restart)
      clientSocket.on('error', (err) => {
        console.error(`[HTTPS] WS client error: ${err.message}`);
        proxySocket.destroy();
      });
      proxySocket.on('error', (err) => {
        console.error(`[HTTPS] WS backend error: ${err.message}`);
        clientSocket.destroy();
      });

      clientSocket.write(
        'HTTP/1.1 101 Switching Protocols\r\n' +
          Object.keys(proxyRes.headers)
            .map((k) => `${k}: ${proxyRes.headers[k]}`)
            .join('\r\n') +
          '\r\n\r\n'
      );
      clientSocket.pipe(proxySocket).pipe(clientSocket);
    });

    proxyReq.on('error', (err) => {
      console.error(`[HTTPS] WS proxy error: ${err.message}`);
      clientSocket.end();
    });

    clientSocket.on('error', (err) => {
      console.error(`[HTTPS] WS client socket error: ${err.message}`);
      proxyReq.destroy();
    });

    proxyReq.end();
  });

  proxy.on('listening', () => {
    const addr = proxy.address();
    console.log(`[HTTPS] Listening on ${addr.address}:${addr.port}`);
    console.log(`[HTTPS] Target: http://${CONFIG.targetHost}:${CONFIG.targetPort}`);
  });

  return proxy;
}

// ============================================================
// Main
// ============================================================

function main() {
  console.log('');
  console.log('================================================');
  console.log('  Hotspot HTTPS Redirect Service');
  console.log('  Intercept domains:');
  CONFIG.interceptDomains.forEach(domain => {
    console.log(`    - https://${domain}`);
  });
  console.log(`  Target: localhost:${CONFIG.targetPort}`);
  console.log('================================================');
  console.log('');

  const dnsServer = createDNSServer();
  dnsServer.bind(CONFIG.dnsPort, '0.0.0.0', () => {
    console.log(`[DNS] Bound 0.0.0.0:${CONFIG.dnsPort}`);
  });

  const httpsProxy = createHTTPSProxy();
  httpsProxy.listen(CONFIG.httpsPort, '0.0.0.0', () => {
    console.log(`[HTTPS] Bound 0.0.0.0:${CONFIG.httpsPort}`);
  });

  console.log('');
  console.log('------------------------------------------------');
  console.log('  Service running. Press Ctrl+C to stop.');
  console.log('------------------------------------------------');
  console.log('');
  console.log('  Client steps:');
  console.log('  1. Connect to this PC hotspot');
  console.log('  2. Visit intercepted domains:');
  CONFIG.interceptDomains.forEach(domain => {
    console.log(`     https://${domain}`);
  });
  console.log('  3. Accept the self-signed certificate warning');
  console.log('');
}

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('\nShutting down...');
  process.exit(0);
});

process.on('SIGTERM', () => {
  console.log('\nShutting down...');
  process.exit(0);
});

// Global error handling — network errors should never crash the process
process.on('uncaughtException', (err) => {
  console.error(`[ERROR] Uncaught: ${err.message}`);
  console.error(err.stack);
  if (err.code === 'EACCES') {
    console.error('Insufficient privileges! Run as Administrator.');
    process.exit(1);
  }
  if (err.code === 'EADDRINUSE') {
    console.error('Port already in use! Close the conflicting program first.');
    console.error(`Run: netstat -ano | findstr :${err.port || 'PORT'}`);
    process.exit(1);
  }
  // All other errors (ECONNRESET, EPIPE, etc.) are non-fatal — keep running
  console.error('[ERROR] Non-fatal error, service continues running.');
});

process.on('unhandledRejection', (reason, promise) => {
  console.error('[ERROR] Unhandled rejection:', reason);
  // Non-fatal — keep running
});

main();
