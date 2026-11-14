import { clientAddress, clientNetwork } from '../../src/common/client-address';

describe('clientNetwork', () => {
  it('keeps an IPv4 address as its own network, also in its IPv4-mapped IPv6 form', () => {
    expect(clientNetwork('203.0.113.7')).toBe('203.0.113.7');
    expect(clientNetwork('::ffff:203.0.113.7')).toBe('203.0.113.7');
    expect(clientNetwork('::FFFF:203.0.113.7')).toBe('203.0.113.7');
  });

  it('puts every address of one IPv6 /64 in the same network, however it is written', () => {
    for (const address of [
      '2001:db8:1:2::1',
      '2001:0db8:0001:0002:ffff:ffff:ffff:ffff',
      '2001:DB8:1:2:0:0:0:9',
      '2001:db8:1:2:abcd::',
      '2001:db8:1:2::192.0.2.1',
      '2001:db8:1:2::1%eth0',
    ]) {
      expect(clientNetwork(address)).toBe('2001:db8:1:2::/64');
    }
  });

  it('tells neighbouring /64s apart', () => {
    expect(clientNetwork('2001:db8:1:3::1')).toBe('2001:db8:1:3::/64');
    expect(clientNetwork('2001:db8:1:2::1')).not.toBe(clientNetwork('2001:db8:1:3::1'));
    expect(clientNetwork('2001:db8::1')).toBe('2001:db8:0:0::/64');
  });

  it('expands short and special IPv6 forms', () => {
    expect(clientNetwork('::')).toBe('0:0:0:0::/64');
    expect(clientNetwork('::1')).toBe('0:0:0:0::/64');
    expect(clientNetwork('fe80::1%eth0')).toBe('fe80:0:0:0::/64');
    expect(clientNetwork('64:ff9b::192.0.2.1')).toBe('64:ff9b:0:0::/64');
    expect(clientNetwork('1:2:3:4:5:6:7::')).toBe('1:2:3:4::/64');
    expect(clientNetwork('1::4:5:6:7:8')).toBe('1:0:0:4::/64');
  });

  it('puts a missing or malformed address in one shared unknown network', () => {
    for (const address of [undefined, '', 'not-an-ip', '1.2.3.4, 5.6.7.8', '::ffff:999.1.1.1']) {
      expect(clientNetwork(address)).toBe('unknown');
    }
  });
});

describe('clientAddress', () => {
  const req = {
    headers: { 'cf-connecting-ip': ' 2001:db8::7 ', 'x-forwarded-for': '5.6.7.8' },
    ip: '5.6.7.8',
    socket: { remoteAddress: '127.0.0.1' },
  };

  it('reads only the configured source', () => {
    expect(clientAddress(req, 'socket')).toBe('127.0.0.1');
    expect(clientAddress(req, 'x-forwarded-for')).toBe('5.6.7.8');
    expect(clientAddress(req, 'cf-connecting-ip')).toBe('2001:db8::7');
    expect(
      clientAddress({ ...req, headers: { 'cf-connecting-ip': 'nope' } }, 'cf-connecting-ip'),
    ).toBe('127.0.0.1');
  });
});
