//go:build !demo

package services

func SetDemoMode(bool)            {}
func IsDemoMode() bool            { return false }
func GetDemoSSHLogs() string      { return "" }
func GetDemoDNSLogs() string      { return "" }
func GetDemoFirewallLogs() string { return "" }
