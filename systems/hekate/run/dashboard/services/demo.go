//go:build demo

package services

import (
	"fmt"
	"math/rand"
	"strings"
	"sync"
	"time"
)

var (
	demoMode bool
	demoMu   sync.RWMutex
	sshLogs  []string
	dnsLogs  []string
	fwLogs   []string
	lastSSH  time.Time
	lastDNS  time.Time
	lastFW   time.Time
)

func SetDemoMode(enabled bool) {
	demoMu.Lock()
	defer demoMu.Unlock()
	demoMode = enabled
	if enabled {
		initDemoData()
	}
}

func IsDemoMode() bool {
	demoMu.RLock()
	defer demoMu.RUnlock()
	return demoMode
}

func initDemoData() {
	now := time.Now()
	sshLogs = generateInitialSSHLogs(now, 20)
	dnsLogs = generateInitialDNSLogs(now, 30)
	fwLogs = generateInitialFWLogs(now, 15)
	lastSSH = now
	lastDNS = now
	lastFW = now
}

var (
	sshUsers = []string{"admin", "moye", "root", "deploy", "backup"}
	sshIPs   = []string{"192.168.1.204", "192.168.1.50", "10.0.0.15", "172.16.0.100", "192.168.1.1"}
	sshKeys  = []string{
		"ED25519 SHA256:G1n54h8yTy1t/W1C3WsWtxXtGusoQcy+2P9wAJ0e1b8",
		"RSA SHA256:nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8",
		"ED25519 SHA256:p2QAMXNIC1TJYWeIOttrVc98/R1BUFWu3/LiyKgUfQM",
	}
)

func generateInitialSSHLogs(now time.Time, count int) []string {
	logs := make([]string, 0, count*2)
	for i := count; i > 0; i-- {
		t := now.Add(-time.Duration(i) * time.Minute * 3)
		logs = append(logs, generateSSHEntry(t)...)
	}
	return logs
}

func generateSSHEntry(t time.Time) []string {
	user := sshUsers[rand.Intn(len(sshUsers))]
	ip := sshIPs[rand.Intn(len(sshIPs))]
	key := sshKeys[rand.Intn(len(sshKeys))]
	port := 50000 + rand.Intn(15000)
	pid := 1000 + rand.Intn(5000)
	ts := t.Format("Jan 02 15:04:05")

	entries := []string{
		fmt.Sprintf("%s hekate sshd-session[%d]: Accepted publickey for %s from %s port %d ssh2: %s",
			ts, pid, user, ip, port, key),
		fmt.Sprintf("%s hekate sshd-session[%d]: pam_unix(sshd:session): session opened for user %s(uid=1000) by (uid=0)",
			ts, pid, user),
	}

	if rand.Float32() < 0.3 {
		entries = append(entries,
			fmt.Sprintf("%s hekate sshd-session[%d]: lastlog_openseek: Couldn't stat /var/log/lastlog: No such file or directory",
				ts, pid))
	}

	return entries
}

var (
	dnsClients = []string{"192.168.1.1", "192.168.1.50", "192.168.1.100", "192.168.1.204", "10.0.0.5"}
	dnsDomains = []string{
		"github.com", "api.github.com", "raw.githubusercontent.com",
		"google.com", "www.google.com", "apis.google.com",
		"config.teams.trafficmanager.net", "teams.microsoft.com",
		"slack.com", "api.slack.com", "edgeapi.slack.com",
		"cloudflare.com", "1.1.1.1.in-addr.arpa",
		"example.com", "api.example.com",
		"ntp.ubuntu.com", "time.cloudflare.com",
		"registry.npmjs.org", "pypi.org",
	}
	dnsTypes = []string{"A", "AAAA", "HTTPS", "MX", "TXT", "CNAME", "PTR"}
)

func generateInitialDNSLogs(now time.Time, count int) []string {
	logs := make([]string, 0, count)
	for i := count; i > 0; i-- {
		t := now.Add(-time.Duration(i) * time.Second * 5)
		logs = append(logs, generateDNSEntry(t))
	}
	return logs
}

func generateDNSEntry(t time.Time) string {
	client := dnsClients[rand.Intn(len(dnsClients))]
	domain := dnsDomains[rand.Intn(len(dnsDomains))]
	qtype := dnsTypes[rand.Intn(len(dnsTypes))]
	pid := 900 + rand.Intn(100)
	ts := t.Format("2006-01-02T15:04:05-07:00")

	return fmt.Sprintf("%s hekate unbound[%d]: [%d:0] info: %s %s. %s IN",
		ts, pid, pid, client, domain, qtype)
}

var (
	fwSrcIPs = []string{"192.168.1.110", "192.168.1.50", "10.0.0.100", "172.16.0.5", "192.168.1.254"}
	fwDstIPs = []string{"224.0.0.22", "255.255.255.255", "224.0.0.251", "239.255.255.250", "8.8.8.8"}
	fwProtos = []string{"TCP", "UDP", "ICMP", "2"}
	fwIfaces = []string{"end0", "wg0", "eth0"}
	fwPorts  = []int{80, 443, 22, 53, 8080, 3389, 445, 139}
)

func generateInitialFWLogs(now time.Time, count int) []string {
	logs := make([]string, 0, count)
	for i := count; i > 0; i-- {
		t := now.Add(-time.Duration(i) * time.Second * 20)
		logs = append(logs, generateFWEntry(t))
	}
	return logs
}

func generateFWEntry(t time.Time) string {
	src := fwSrcIPs[rand.Intn(len(fwSrcIPs))]
	dst := fwDstIPs[rand.Intn(len(fwDstIPs))]
	proto := fwProtos[rand.Intn(len(fwProtos))]
	iface := fwIfaces[rand.Intn(len(fwIfaces))]
	ts := t.Format("2006-01-02T15:04:05-07:00")

	length := 40 + rand.Intn(1000)
	ttl := 1 + rand.Intn(64)

	base := fmt.Sprintf("%s hekate kernel: FW_DROP: IN= OUT=%s SRC=%s DST=%s LEN=%d TOS=0x00 PREC=0xC0 TTL=%d ID=0 DF PROTO=%s",
		ts, iface, src, dst, length, ttl, proto)

	if proto == "TCP" || proto == "UDP" {
		sport := fwPorts[rand.Intn(len(fwPorts))]
		dport := fwPorts[rand.Intn(len(fwPorts))]
		base += fmt.Sprintf(" SPT=%d DPT=%d", sport, dport)
	}

	return base + " MARK=0x94"
}

func GetDemoSSHLogs() string {
	demoMu.Lock()
	defer demoMu.Unlock()

	now := time.Now()
	if now.Sub(lastSSH) > 8*time.Second && rand.Float32() < 0.4 {
		sshLogs = append(sshLogs, generateSSHEntry(now)...)
		if len(sshLogs) > 100 {
			sshLogs = sshLogs[len(sshLogs)-100:]
		}
		lastSSH = now
	}

	return strings.Join(sshLogs, "\n")
}

func GetDemoDNSLogs() string {
	demoMu.Lock()
	defer demoMu.Unlock()

	now := time.Now()
	if now.Sub(lastDNS) > 2*time.Second {
		count := 1 + rand.Intn(3)
		for i := 0; i < count; i++ {
			dnsLogs = append(dnsLogs, generateDNSEntry(now.Add(time.Duration(i)*100*time.Millisecond)))
		}
		if len(dnsLogs) > 200 {
			dnsLogs = dnsLogs[len(dnsLogs)-200:]
		}
		lastDNS = now
	}

	return strings.Join(dnsLogs, "\n")
}

func GetDemoFirewallLogs() string {
	demoMu.Lock()
	defer demoMu.Unlock()

	now := time.Now()
	if now.Sub(lastFW) > 5*time.Second && rand.Float32() < 0.6 {
		fwLogs = append(fwLogs, generateFWEntry(now))
		if len(fwLogs) > 100 {
			fwLogs = fwLogs[len(fwLogs)-100:]
		}
		lastFW = now
	}

	return strings.Join(fwLogs, "\n")
}
