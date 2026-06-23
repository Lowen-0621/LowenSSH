import 'package:flutter_test/flutter_test.dart';
import 'package:lowenssh/core/guard.dart';

void main() {
  group('CommandGuard 门禁三态', () {
    group('DENY —— 毁灭性操作直接拒', () {
      const cases = [
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
      ];
      for (final cmd in cases) {
        test('拒绝: $cmd', () {
          expect(evaluate(cmd).decision, Decision.deny);
        });
      }
    });

    group('ASK —— 有副作用需确认', () {
      const cases = [
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
      ];
      for (final cmd in cases) {
        test('询问: $cmd', () {
          expect(evaluate(cmd).decision, Decision.ask);
        });
      }
    });

    group('ALLOW —— 只读/安全命令放行', () {
      const cases = [
        'df -h',
        'free -m',
        'ps aux | grep java',
        'cat /etc/nginx/nginx.conf',
        'tail -n 100 /var/log/syslog',
        'ls -la',
        'add-apt-repository ppa:x', // \b 不应误伤 add
      ];
      for (final cmd in cases) {
        test('放行: $cmd', () {
          expect(evaluate(cmd).decision, Decision.allow);
        });
      }
    });

    group('复合命令取最严', () {
      test('ls && rm -rf / —— 整条 DENY', () {
        expect(evaluate('ls && rm -rf /').decision, Decision.deny);
      });
      test('df -h ; kill 1 —— 整条 ASK', () {
        expect(evaluate('df -h ; kill 1').decision, Decision.ask);
      });
      test('cat a | grep b —— 全只读 ALLOW', () {
        expect(evaluate('cat a | grep b').decision, Decision.allow);
      });
    });

    group('边界', () {
      test('空命令 ALLOW', () {
        expect(evaluate('').decision, Decision.allow);
        expect(evaluate('   ').decision, Decision.allow);
      });
    });
  });
}
