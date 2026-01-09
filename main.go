package main

import (
	"encoding/binary"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"
)

// 全局配置变量
var (
	port     int
	username string
	password string
)

func main() {
	// 1. 解析命令行参数
	flag.IntVar(&port, "port", 1080, "SOCKS5 监听端口")
	flag.StringVar(&username, "user", "", "认证用户名")
	flag.StringVar(&password, "pass", "", "认证密码")
	flag.Parse()

	// 简单的参数校验
	if username == "" || password == "" {
		fmt.Println("错误: 必须指定用户名和密码")
		fmt.Println("用法示例: ./socks5 -port 1080 -user admin -pass 123456")
		os.Exit(1)
	}

	// 2. 启动监听
	addr := fmt.Sprintf(":%d", port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		fmt.Printf("启动失败: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("SOCKS5 服务已启动 (端口: %d, 用户: %s)\n", port, username)

	// 3. 循环接收连接
	for {
		conn, err := listener.Accept()
		if err != nil {
			continue // 忽略连接错误，保持静默
		}
		go handleClient(conn)
	}
}

func handleClient(conn net.Conn) {
	defer conn.Close()

	// 设置超时防止僵尸连接
	conn.SetDeadline(time.Now().Add(60 * time.Second))

	// --- 1. 握手阶段 ---
	buf := make([]byte, 256)
	// 读取版本和方法数量
	if _, err := io.ReadFull(conn, buf[:2]); err != nil {
		return
	}
	ver, nMethods := buf[0], buf[1]
	if ver != 0x05 {
		return
	}

	// 读取方法列表
	methods := make([]byte, nMethods)
	if _, err := io.ReadFull(conn, methods); err != nil {
		return
	}

	// 响应服务端选择的方法 (0x02: 用户名密码认证)
	// 简单起见，这里假设客户端一定会发 0x02，不严谨检查方法列表了，因为是我们自己用
	conn.Write([]byte{0x05, 0x02})

	// --- 2. 认证阶段 ---
	// 读取版本和用户名长度
	if _, err := io.ReadFull(conn, buf[:2]); err != nil {
		return
	}
	authVer, uLen := buf[0], buf[1]
	if authVer != 0x01 {
		return
	}

	// 读取用户名
	uNameBytes := make([]byte, uLen)
	if _, err := io.ReadFull(conn, uNameBytes); err != nil {
		return
	}
	clientUser := string(uNameBytes)

	// 读取密码长度
	if _, err := io.ReadFull(conn, buf[:1]); err != nil {
		return
	}
	pLen := buf[0]

	// 读取密码
	passBytes := make([]byte, pLen)
	if _, err := io.ReadFull(conn, passBytes); err != nil {
		return
	}
	clientPass := string(passBytes)

	// 校验账号密码
	if clientUser != username || clientPass != password {
		conn.Write([]byte{0x01, 0x01}) // 认证失败
		return
	}

	conn.Write([]byte{0x01, 0x00}) // 认证成功

	// 取消握手阶段的超时，进入数据传输阶段
	conn.SetDeadline(time.Time{})

	// --- 3. 请求处理 ---
	// ver(1) + cmd(1) + rsv(1) + atyp(1)
	header := make([]byte, 4)
	if _, err := io.ReadFull(conn, header); err != nil {
		return
	}

	if header[0] != 0x05 || header[1] != 0x01 { // 仅支持 CONNECT (0x01)
		return
	}

	var targetAddr string
	switch header[3] {
	case 0x01: // IPv4
		ipv4 := make([]byte, 4)
		if _, err := io.ReadFull(conn, ipv4); err != nil {
			return
		}
		targetAddr = net.IP(ipv4).String()
	case 0x03: // Domain
		if _, err := io.ReadFull(conn, buf[:1]); err != nil {
			return
		}
		domainLen := buf[0]
		domain := make([]byte, domainLen)
		if _, err := io.ReadFull(conn, domain); err != nil {
			return
		}
		targetAddr = string(domain)
	case 0x04: // IPv6
		ipv6 := make([]byte, 16)
		if _, err := io.ReadFull(conn, ipv6); err != nil {
			return
		}
		targetAddr = fmt.Sprintf("[%s]", net.IP(ipv6).String())
	default:
		return
	}

	// 读取端口
	portBuf := make([]byte, 2)
	if _, err := io.ReadFull(conn, portBuf); err != nil {
		return
	}
	destPort := binary.BigEndian.Uint16(portBuf)
	dest := fmt.Sprintf("%s:%d", targetAddr, destPort)

	// --- 4. 建立远程连接 ---
	destConn, err := net.DialTimeout("tcp", dest, 10*time.Second)
	if err != nil {
		conn.Write([]byte{0x05, 0x05, 0x00, 0x01, 0, 0, 0, 0, 0, 0}) // Connection refused
		return
	}
	defer destConn.Close()

	// 响应连接成功
	conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0})

	// --- 5. 数据转发 ---
	var wg sync.WaitGroup
	wg.Add(2)

	// 本地 -> 远程
	go func() {
		defer wg.Done()
		defer destConn.Close()
		io.Copy(destConn, conn)
	}()

	// 远程 -> 本地
	go func() {
		defer wg.Done()
		defer conn.Close()
		io.Copy(conn, destConn)
	}()

	wg.Wait()
}
