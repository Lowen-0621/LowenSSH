import { describe, it, expect } from 'vitest'
import { evaluate } from './guard.js'

describe('CommandGuard 门禁三态', () => {
  describe('DENY —— 毁灭性操作直接拒', () => {
    it.each([
      'rm -rf /',
      'rm -fr /var/data',
      'rm -r -f /tmp',
      'mkfs.ext4 /dev/sdb',
      'dd if=/dev/zero of=/dev/sda',
      'shutdown -h now',
      'reboot',
      'halt',
      'echo x > /dev/sda',
      ':(){ :|:& };:',
      'mv /important /dev/null',
      'find /tmp -name "*.log" -delete',
      'find / -name core -exec rm {} \\;',
    ])('拒绝: %s', (cmd) => {
      expect(evaluate(cmd).decision).toBe('DENY')
    })
  })

  describe('ASK —— 有副作用需确认', () => {
    it.each([
      'rm /tmp/old.log',
      'kill 1234',
      'systemctl stop nginx',
      'systemctl restart docker',
      'service mysql stop',
      'chmod 777 /etc/passwd',
      'chown root:root /opt',
      'apt-get install vim',
      'yum remove httpd',
      'truncate -s 0 app.log',
      'echo data > /etc/config',
    ])('询问: %s', (cmd) => {
      expect(evaluate(cmd).decision).toBe('ASK')
    })
  })

  describe('ALLOW —— 只读/安全命令放行', () => {
    it.each([
      'df -h',
      'free -m',
      'ps aux | grep java',
      'cat /etc/nginx/nginx.conf',
      'tail -n 100 /var/log/syslog',
      'ls -la',
      'add-apt-repository ppa:x', // \b 不应误伤 add
    ])('放行: %s', (cmd) => {
      expect(evaluate(cmd).decision).toBe('ALLOW')
    })
  })

  describe('复合命令取最严', () => {
    it('ls && rm -rf / —— 整条 DENY', () => {
      expect(evaluate('ls && rm -rf /').decision).toBe('DENY')
    })
    it('df -h ; kill 1 —— 整条 ASK', () => {
      expect(evaluate('df -h ; kill 1').decision).toBe('ASK')
    })
    it('cat a | grep b —— 全只读 ALLOW', () => {
      expect(evaluate('cat a | grep b').decision).toBe('ALLOW')
    })
  })

  describe('边界', () => {
    it('空命令 ALLOW', () => {
      expect(evaluate('').decision).toBe('ALLOW')
      expect(evaluate('   ').decision).toBe('ALLOW')
    })
  })
})
