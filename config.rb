# encoding: utf-8

module BMConfig
	Major_version = 1
	Minor_version = 0
	App_version = "#{Major_version}.#{Minor_version}"
	Protocol_version = 3
	User_agent = "CL-Bitmessage #{App_version}"

	Magic = 0xE9BEB4D9
	BootNodes = [
		# ['23.239.9.147', 8444],
		['98.218.125.214', 8444],
		['192.121.170.162', 8444],	
		['108.61.72.12', 28444],
		['158.222.211.81', 8080],
		['79.163.240.110', 8446],
		['178.62.154.250', 8444],
		['178.62.155.6', 8444],
		['178.62.155.8', 8444],
		['68.42.42.120', 8444],
	]
	RecordLife = 3600*3

	InventoryDir = "./inventory"
	NonceTrialsPerByte = 1000
	PayloadLengthExtraBytes = 1000

	Log_file = nil
	Log_level = :info
end
