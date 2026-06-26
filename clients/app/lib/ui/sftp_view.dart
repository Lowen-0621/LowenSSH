import 'package:flutter/material.dart';
import '../theme.dart';

/// 文件项占位 model（Step 4 接 core/ssh.dart 的 SFTP listdir）
class _FileItem {
  final IconData icon;
  final String name;
  final String? meta; // 大小或权限
  final bool isDir;
  final bool uploading;
  const _FileItem(this.icon, this.name, this.meta,
      {this.isDir = false, this.uploading = false});
}

/// SFTP 双栏文件管理器 —— 本地 | 传输控制 | 远程
/// 对应设计稿 .sftp-view。图标统一 Material 线性。
class SftpView extends StatelessWidget {
  const SftpView({super.key});

  static const _folder = Icons.folder_outlined;
  static const _file = Icons.description_outlined;
  static const _archive = Icons.inventory_2_outlined;
  static const _image = Icons.image_outlined;

  static const _local = [
    _FileItem(_folder, '..', null, isDir: true),
    _FileItem(_folder, 'project', 'drwxr-xr-x', isDir: true),
    _FileItem(_file, 'app.conf', '2.1 KB'),
    _FileItem(_archive, 'release.tar.gz', '48 MB'),
    _FileItem(_image, 'logo.png', '31 KB'),
  ];

  static const _remote = [
    _FileItem(_folder, '..', null, isDir: true),
    _FileItem(_folder, 'html', 'drwxr-xr-x', isDir: true),
    _FileItem(_folder, 'logs', 'drwxr-xr-x', isDir: true),
    _FileItem(_archive, 'release.tar.gz', '67%', uploading: true),
    _FileItem(_file, 'nginx.conf', '-rw-r--r--'),
    _FileItem(_file, 'index.html', '-rw-r--r--'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.base,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _fsPane('~/Downloads', null, _local, rightBorder: true),
                ),
                Expanded(
                  child: _fsPane('/var/www', 'web01', _remote),
                ),
              ],
            ),
          ),
          _status(),
        ],
      ),
    );
  }

  // 工具条：本地路径 | 上传/下载 | 远程路径
  Widget _toolbar() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: AppColors.mantle,
          border: Border(bottom: BorderSide(color: AppColors.surface0)),
        ),
        child: Row(
          children: [
            Expanded(child: _pathBar('本地', '~/Downloads', remote: false)),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _arrow(Icons.arrow_upward, '上传'),
                const SizedBox(height: 5),
                _arrow(Icons.arrow_downward, '下载'),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(child: _pathBar('远程 · web01', '/var/www', remote: true)),
          ],
        ),
      );

  Widget _pathBar(String side, String path, {required bool remote}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.base,
          border: Border.all(color: AppColors.surface0),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Text(side.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    letterSpacing: .5,
                    color: remote ? AppColors.blue : AppColors.overlay)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(path,
                  style: const TextStyle(
                      fontFamily: kMonoFont,
                      fontSize: 11.5,
                      color: AppColors.subtext)),
            ),
          ],
        ),
      );

  Widget _arrow(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surface0,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.text),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppColors.text)),
          ],
        ),
      );

  // 单侧文件面板（头 + 列表）
  Widget _fsPane(String head, String? host, List<_FileItem> files,
          {bool rightBorder = false}) =>
      Container(
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
                color: rightBorder ? AppColors.surface0 : Colors.transparent),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: const BoxDecoration(
                color: AppColors.mantle,
                border: Border(bottom: BorderSide(color: AppColors.surface0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_open_outlined,
                      size: 14, color: AppColors.subtext),
                  const SizedBox(width: 7),
                  Text(head,
                      style: const TextStyle(
                          fontFamily: kMonoFont,
                          fontSize: 11.5,
                          color: AppColors.subtext)),
                  if (host != null) ...[
                    const Spacer(),
                    Text(host,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.green)),
                  ],
                ],
              ),
            ),
            // 列表
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                children: [for (final f in files) _fileRow(f)],
              ),
            ),
          ],
        ),
      );

  Widget _fileRow(_FileItem f) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: f.uploading ? AppColors.blue.withValues(alpha: .10) : null,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          children: [
            Icon(f.icon,
                size: 15,
                color: f.isDir ? AppColors.blue : AppColors.subtext),
            const SizedBox(width: 9),
            Expanded(
              child: Text(f.name,
                  style: TextStyle(
                      fontSize: 12,
                      color: f.isDir ? AppColors.blue : AppColors.text)),
            ),
            // 上传中显示进度图标
            if (f.uploading)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.upload, size: 12, color: AppColors.blue),
              ),
            if (f.meta != null)
              Text(f.meta!,
                  style: TextStyle(
                      fontSize: 10,
                      color: f.uploading
                          ? AppColors.blue
                          : AppColors.overlay)),
          ],
        ),
      );

  // 底部传输状态条
  Widget _status() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          color: AppColors.crust,
          border: Border(top: BorderSide(color: AppColors.surface0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.upload, size: 12, color: AppColors.blue),
                SizedBox(width: 5),
                Text('release.tar.gz · 32.1/48 MB · 8.4 MB/s · 剩 2s',
                    style: TextStyle(
                        fontFamily: kMonoFont,
                        fontSize: 10.5,
                        color: AppColors.blue)),
              ],
            ),
            Text('双击文件用内置编辑器打开 · 拖拽可跨栏传输',
                style: TextStyle(
                    fontFamily: kMonoFont,
                    fontSize: 10.5,
                    color: AppColors.overlay)),
          ],
        ),
      );
}
