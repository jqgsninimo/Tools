#!/bin/zsh

# 未定义常量
typeset undefined="<Undefined>"
# 脚本名称
typeset sh_name=${0##*/}

# 说明
usage() {
	echo -e "\e[32m"  # 设置颜色为绿色
	cat <<EOF 1>&2
Usage: 
  - Read Clients  : $sh_name -r [-c <Client ID>] [-a <IP Address>]
  - Insert Client : $sh_name -i -c <Client ID> [-a <IP Address>]
  - Modify Client : $sh_name -m -c <Client ID> [-a <IP Address>]
  - Delete Clients: $sh_name -d [-c <Client ID>] [-a <IP Address>]
EOF
  echo -e "\e[0m"  # 重置颜色为默认
	exit 1
}

# 显示消息
show() {
  local message=$1
  local type=${2:-info}
  local color_code=""

  # 根据类型选择颜色
  case $type in
    "error") color_code="\e[31m";;  # 红色
		"warn") color_code="\e[33m";;  	# 黄色
		"info") color_code="\e[34m";;		# 蓝色
		"ask") color_code="\e[35m";;		# 紫色
    "result") color_code="\e[32m";; # 绿色
    "debug") color_code="\e[90m";;  # 灰色
    *) color_code="";;  # 默认颜色
  esac

  # 显示带颜色的消息
  echo -e "${color_code}[${(U)type}] $message\e[0m"
}

# 获取设定值
conf() {
	echo $(grep -oP "^$2\s+\K.+$" $1 2>/dev/null)
}

table() {
	# 定义表格的标题和内容
	local data=(${(P)${1}})
	local column_count=$2
	local has_header=${3:-true}

	# 计算列宽
	local widths=($(repeat $column_count {echo 0}))

	for index in $(seq 1 $#data); do
		local cell=${data[$index]}
		local column_index=$(($index % $column_count))
		if ((column_index == 0)); then column_index=$column_count; fi
		local cell_width=${#cell}
		if ((cell_width > ${widths[column_index]})); then widths[$column_index]=$cell_width; fi
	done

	# 打印表格上边框
	local line=($widths)
	for i in $(seq 1 $#line); do
		local tmp=($(repeat ${line[$i]} {echo ─}))
		line[$i]=${(j::)tmp}
	done
	printf "┌─${(j:─┬─:)line}─┐\n"

	# 打印数据
	for index in $(seq 1 $#data); do
		local cell=${data[$index]}
		local format="│ %-*s "
		local column_index=$(($index % $column_count))
		if ((column_index == 0)); then
			column_index=$column_count
			format="${format}│\n"
		fi
		local width=${widths[$column_index]}
		printf $format $width $cell

		# 打印表格标题与内容的分隔线
		if ((has_header == true && index == column_count)); then
			local line=($widths)
			for i in $(seq 1 $#line); do
				local tmp=($(repeat ${line[$i]} {echo ─}))
				line[$i]=${(j::)tmp}
			done
			printf "├─${(j:─┼─:)line}─┤\n"
		fi
	done

	# 打印表格下边框
	local line=($widths)
	for i in $(seq 1 $#line); do
		local tmp=($(repeat ${line[$i]} {echo ─}))
		line[$i]=${(j::)tmp}
	done
	printf "└─${(j:─┴─:)line}─┘\n"
}

# 将IP地址转化为二进制字符串
binary_ip() {
	IFS='.' read -A parts <<< $1
	for i in $(seq 1 $#parts); do
		parts[$i]=$(printf "%08d" $(echo "obase=2; ${parts[$i]}" | bc))
	done
	echo ${(j::)parts}
}

# 检查IP是否处于子网内
check_ip_subnet() {
	# 获得参数
  local ip=$1
  local net=$2

	# 获得子网地址和子网前缀长度
	local len
	# 如果子网为CIDR表示法
	if [[ $net =~ "^(([0-9]+\.){3}[0-9]+)/([0-9]+)$" ]]; then
  	net="${match[1]}"
		len="${match[3]}"
	# 如果子网为掩码表示法
	elif [[ $net =~ "^(([0-9]+\.){3}[0-9]+)[[:space:]]+(([0-9]+\.){3}[0-9]+)$" ]]; then
		net="${match[1]}"
		len=${$(binary_ip ${match[3]})%%0*}
		len=${#len}
	# 如果格式错误，直接返回假
	else 
		echo false; return
	fi

	# 将子网地址和IP地址转换为二进制
	net=$(binary_ip $net)
	ip=$(binary_ip $ip)

	# 检查IP地址前缀位和子网地址前缀位是否相同
	if [[ ${ip:0:$len} == ${net:0:$len} ]]; then
		if [[ ${ip:$len} == $(printf "%0$((32 - len))d" 1) ]]; then
			echo first
		else
			echo true
		fi
	else
		echo false
	fi
}

# 检查IP地址是否合规
check_ip() {
	# 判断是否已存在
	if [[ -v clients[(r)$client_ip] ]]; then
		show "IP address [$client_ip] has been assigned." error
		exit 1
	fi

	# 判断是否符合IPv4格式
	if [[ ! $client_ip =~ "^([0-9]{1,3}\.){3}[0-9]{1,3}$" ]]; then
  		show "IP address [$client_ip] is not a valid IPv4 address." error
			exit 1
	fi

	# 判断是否属于子网
	local result=$(check_ip_subnet $client_ip $ovpn_net)
	if [[ $result == false ]]; then
		show "IP address [$client_ip] is not within OpenVPN NET [$ovpn_net]." error
		exit 1
	fi

	# 判断是否为子网首地址
	if [[ $result == first ]]; then
		show "IP address [$client_ip] cannot be the first address of OpenVPN NET [$ovpn_net]." error
		exit 1
	fi

	# 判断低8位是否模4余1
	local part=${client_ip##*.}
	if (( part % 4 != 1 )); then
		show "The rightmost part of the client's IP address must be equal to n*4+1, where n is a natural number." error
		exit 1
	fi
}

# 检索客户信息
select_clients() {
	# 初始化客户ID数组
	typeset -ag client_ids=()
	client_id=${client_id:-'.*'}
  client_ip=${client_ip:-'.*'}
	local data=("Client ID" "IP Address" "OVPN File Path")
	for id ip in ${(kv)clients}; do
		if [[ ! $id =~ $client_id ]] || [[ ! $ip =~ $client_ip ]]; then
  		continue
		fi
		client_ids+=$id
		data+="$id"
		data+="$ip"
		data+="${ovpn_home}client/${id}.ovpn"
	done

	# 输出检索结果
	if [[ -z ${client_ids[@]} ]]; then
    show "No client that meets the criteria was found." info
	else
		table data 3
	fi
}

# 新增客户
insert_client() {
	# 判断是否提供ID
	if [ -z "$client_id" ]; then
		show "Please provide the ID of the new client using the -c parameter." error
  	exit 1
	fi
	# 判断ID是否重复
	if [[ -v clients[$client_id] ]]; then
  	show "Client [$client_id] already exists." error
		exit 1
	fi

	# 判断IP是否合规
	if [[ -n "$client_ip" ]]; then
		check_ip
	fi

	# 创建客户
	# 进入easy-rsa目录
	cd easy-rsa

	# ① 为客户创建密钥对和请求文件并签发证书
	./easyrsa build-client-full $client_id nopass > /dev/null 2>&1
	
	# 进入OpenVPN目录
	cd ..

	# ② 配置IP地址
	if [[ -n "$client_ip" ]]; then
		rm -f ccd/${client_id}
		echo "ifconfig-push $client_ip ${client_ip%.*}.$((${client_ip##*.}+1))" >> ccd/${client_id}
	fi

	# ③ 生成客户配置文件
	cat >client/${client_id}.ovpn <<EOF
client
dev tun
proto udp
remote $ovpn_ip $ovpn_port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
key-direction 1
<ca>
$ca_crt
</ca>
<tls-auth>
$ta_key
</tls-auth>
<cert>
$(openssl x509 -in easy-rsa/pki/issued/${client_id}.crt)
</cert>
<key>
$(<easy-rsa/pki/private/${client_id}.key)
</key>
EOF

	# 显示结果
	show "Client [$client_id] has been successfully created." result
	reload_clients
	select_clients
}

# 修改客户
modify_client() {
	# 判断是否提供ID
	if [ -z "$client_id" ]; then
		show "Please provide the ID of the client you want to modify using the -c parameter." error
  	exit 1
	fi
	# 判断ID是否存在
	if [[ -z clients[$client_id] ]]; then
  	show "Client [$client_id] does not exist." error
		exit 1
	fi

	# 判断是否提供IP
	if [ -z "$client_ip" ]; then
		if [[ "${clients[$client_id]}" == $undefined ]]; then
			show "Client [$client_id] is not assigned a fixed IP address." info
			exit 1
		fi
		show "Do you want to delete the fixed IP address [${clients[$client_id]}] for client [$client_id]?" ask
		echo -n "Yes(y) or No: "
		read response
		if [[ ${response:l} != "y" && ${response:l} != "yes" ]]; then
    	exit 1	
		fi
		rm -f ${ovpn_home}ccd/${client_id}
	else
		# 判断IP是否合规
		check_ip

		# 配置IP地址
		rm -f ccd/${client_id}
		echo "ifconfig-push $client_ip ${client_ip%.*}.$((${client_ip##*.}+1))" >> ccd/${client_id}
	fi

	# 显示结果
	show "Client [$client_id] has been successfully modified." result
	reload_clients
	select_clients
}

# 删除客户
delete_clients() {
	client_id=${client_id:-'.*'}
  client_ip=${client_ip:-'.*'}
	# 收集符合删除条件的客户ID
	select_clients

	# 没有符合删除条件的客户，直接退出
	if [[ -z ${client_ids[@]} ]]; then
		exit 1
	fi

	# 确认是否删除
	show "Should the above-mentioned clients be deleted?" ask
	echo -n "Yes(y) or No: "
	read response
	if [[ ${response:l} != "y" && ${response:l} != "yes" ]]; then
    exit 1	
	fi

	# 删除客户相关文件
	for id in "${client_ids[@]}"; do
		# ①删除请求文件
		rm -f easy-rsa/pki/reqs/${id}.req
		# ②删除密钥文件
		rm -f easy-rsa/pki/private/${id}.key
		# ③删除证书文件
		rm -f easy-rsa/pki/issued/${id}.crt
		# ④删除地址文件
		rm -f ccd/${id}
		# ⑤删除配置文件
		rm -f client/${id}.ovpn
	done
	show "The clients have been deleted." result
}

# 获得所有客户信息
reload_clients() {
	typeset -gA clients
	for file in client/*; do
		local id=$(basename ${file%.*})
		local ip=$(conf "ccd/$id" ifconfig-push | awk '{print $1}')
		clients[$id]=${ip:-$undefined}
	done
}

# 获得OVPN运行命令
ovpn_cmd=`ps axocommand | grep "openvpn " | grep -v grep`
if [ -z "$ovpn_cmd" ]; then
	show "OpenVPN server is not running. Please start it first." error
  exit 1
fi

# 提取OVPN目录和配置文件名
regex='--cd (.*) --config (.*)'
if [[ $ovpn_cmd =~ $regex ]]; then
	ovpn_home="${match[1]}"
	ovpn_conf="${match[2]}"
else
	show "Failed to retrieve OpenVPN home and CONF file name." error
  exit 1
fi

# 判断OVPN目录是否存在
if [ ! -d "$ovpn_home" ]; then
  show "The OpenVPN HOME does not exist: $ovpn_home" error
  exit 1
fi

# 进入OVPN目录
cd $ovpn_home

# 判断OVPN配置文件是否存在
if [ ! -f "$ovpn_conf" ]; then
  show "The OpenVPN CONF file does not exist: $ovpn_conf" error
  exit 1	
fi

# 获取服务器公网IP
ovpn_ip=$(curl -s https://api.ipify.org)
# 获取OVPN服务端口号
ovpn_port=$(conf $ovpn_conf port)
# 获取OVPN子网
ovpn_net=$(conf $ovpn_conf server)

# 获取CA证书
ca_crt=$(<"$(conf $ovpn_conf ca)")
# 获取TA密钥
ta_key=$(egrep -v "^#" ta.key)

# 若client目录不存在，创建之
mkdir -p client
# 获得所有客户信息
reload_clients

local mode=h
while getopts 'hrimdc:a:' args; do
  case $args in
		h|r|i|m|d) mode=$args;;
    c) client_id=$OPTARG;;
    a) client_ip=$OPTARG;;
	esac
done

case $mode in
	h) usage;;
	r) select_clients;;
	i) insert_client;;
	m) modify_client;;
	d) delete_clients;;
esac