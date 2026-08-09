package com.lowenssh.ssh;

/**
 * 远程文件/目录的元信息，SFTP 列目录用。
 *
 * @param name  文件名（不含路径）
 * @param path  绝对路径
 * @param size  字节大小（目录为 0）
 * @param isDir 是否目录
 * @param perms 权限字符串，如 "rwxr-xr-x"
 * @param mtime 修改时间（Unix 秒）
 */
public record RemoteFile(
        String name,
        String path,
        long size,
        boolean isDir,
        String perms,
        long mtime
) {}
