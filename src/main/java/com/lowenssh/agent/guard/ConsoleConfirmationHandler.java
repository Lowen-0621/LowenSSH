package com.lowenssh.agent.guard;

import java.util.Scanner;

/**
 * 控制台确认实现 —— 前台运行时走 System.in，真人敲 y/n。
 *
 * 用于 CLI 交互入口（CommandLineRunner 模式）演示"执行前人工确认"这一刀。
 * Web 后台进程没有终端，别用这个，用 AutoConfirmationHandler。
 */
public class ConsoleConfirmationHandler implements ConfirmationHandler {

    // System.in 全局只有一个，复用同一个 Scanner，别每次 new（会吃掉缓冲）
    private final Scanner scanner = new Scanner(System.in);

    @Override
    public boolean confirm(String command, String reason) {
        System.out.println("\n⚠️  需要确认：" + reason);
        System.out.println("    命令: " + command);
        System.out.print("    执行吗？(y/n): ");
        String line = scanner.nextLine().trim().toLowerCase();
        return line.equals("y") || line.equals("yes");
    }
}
