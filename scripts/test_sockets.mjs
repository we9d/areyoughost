import net from 'net';
import dgram from 'dgram';

const TCP_PORT = 3001;
const UDP_PORT = 3002;
const HOST = '127.0.0.1';

async function testTcp() {
  console.log('--- Testing Custom TCP Framing ---');
  return new Promise((resolve, reject) => {
    const client = new net.Socket();
    
    client.connect(TCP_PORT, HOST, () => {
      console.log('> TCP Connected');
      
      // We simulate a LoginRequest (Type 0x01)
      const payload = Buffer.from(JSON.stringify({ username: 'test_user' }), 'utf-8');
      
      const header = Buffer.alloc(3);
      header.writeUInt8(0x01, 0); // Type
      header.writeUInt16BE(payload.length, 1); // Length 2-bytes big-endian
      
      const frame = Buffer.concat([header, payload]);
      
      console.log(`> Sending TCP Frame (${frame.length} bytes): Type=0x01, Len=${payload.length}`);
      client.write(frame);

      // Give it a second to process then close
      setTimeout(() => {
        client.destroy();
        resolve();
      }, 500);
    });

    client.on('error', (err) => {
      console.error('TCP Error:', err.message);
      reject(err);
    });
  });
}

async function testUdp() {
  console.log('\n--- Testing Custom UDP Datagrams ---');
  return new Promise((resolve) => {
    const client = dgram.createSocket('udp4');
    
    // Type (0x50 Heartbeat) + 16 Bytes UUID + Payload (empty)
    const typeBuf = Buffer.alloc(1);
    typeBuf.writeUInt8(0x50, 0);

    // Dummy UUID bytes (16 bytes)
    const uuidBuf = Buffer.alloc(16);
    uuidBuf.fill(0xAA); // Just 10101010 for visual debug

    const payload = Buffer.from('alive');
    const datagram = Buffer.concat([typeBuf, uuidBuf, payload]);

    console.log(`> Sending UDP Datagram (${datagram.length} bytes) to ${HOST}:${UDP_PORT}`);
    client.send(datagram, UDP_PORT, HOST, (err) => {
      if (err) console.error('UDP Send Error:', err);
      else console.log('> UDP Sent Successfully');
      client.close();
      resolve();
    });
  });
}

async function main() {
  try {
    await testTcp();
    await testUdp();
    console.log('\n✅ Test scripts completed.');
  } catch (err) {
    console.error('Test Failed:', err);
  }
}

main();
