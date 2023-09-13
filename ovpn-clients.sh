#!/bin/zsh

# 全局常量
# 脚本名称
typeset sh_name=${0##*/}
# 脚本版本
typeset sh_version=2.0
# 脚本描述
typeset sh_description="OpenVPN client accounts manager"
# 未定义时显示内容
typeset undefined="<Undefined>"
# 客户端ID正则表达式
typeset sh_id_regex="^[a-z0-9-]+$"


# 说明
usage() {
	echo -ne "\e[32m"  # 设置颜色为绿色
	separator_line ovpn-clients
	echo " Version     : v$sh_version"
	echo " Description : $sh_description"
	separator_line "Usage"
	cat <<EOF 1>&2
  - Wizard mode   : $sh_name [-g]
  - Read Clients  : $sh_name -r [-c <Client ID>] [-a <IP Address>]
  - Insert Client : $sh_name -i -c <Client ID> [-a <IP Address>]
  - Modify Client : $sh_name -m -c <Client ID> [-a <IP Address>]
  - Delete Clients: $sh_name -d [-c <Client ID>] [-a <IP Address>]
EOF
  echo -ne "\e[0m"  # 重置颜色为默认
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
  echo -e "${color_code}[${(U)type}]\e[0m $message"
}

# 获取设定值
conf() {
	local value=$(grep -oP "^$2\s+\K.+$" $1 2>/dev/null)
	echo ${value:-$3}
}

table() {
	# 定义表格的标题和内容
	local data=(${(P)${1}})
	local column_count=$2
	local has_header=${3:-true}

	# 计算列宽
	local widths=($(repeat $column_count {echo 0}))

	for index in $(seq 1 $#data); do
		local cell=$data[$index]
		local column_index=$((index % column_count))
		if ((column_index == 0)); then column_index=$column_count; fi
		local cell_width=$#cell
		if ((cell_width > widths[column_index])); then widths[$column_index]=$cell_width; fi
	done

	# 打印表格上边框
	local line=($widths)
	for i in $(seq 1 $#line); do
		local tmp=($(repeat $line[$i] {echo ─}))
		line[$i]=${(j::)tmp}
	done
	printf "┌─${(j:─┬─:)line}─┐\n"

	# 打印数据
	for index in $(seq 1 $#data); do
		local cell=$data[$index]
		local format="│ %-*s "
		local column_index=$((index % column_count))
		if ((column_index == 0)); then
			column_index=$column_count
			format="${format}│\n"
		fi
		local width=$widths[$column_index]
		printf $format $width $cell

		# 打印表格标题与内容的分隔线
		if ((has_header == true && index == column_count)); then
			local line=($widths)
			for i in $(seq 1 $#line); do
				local tmp=($(repeat $line[$i] {echo ─}))
				line[$i]=${(j::)tmp}
			done
			printf "├─${(j:─┼─:)line}─┤\n"
		fi
	done

	# 打印表格下边框
	local line=($widths)
	for i in $(seq 1 $#line); do
		local tmp=($(repeat $line[$i] {echo ─}))
		line[$i]=${(j::)tmp}
	done
	printf "└─${(j:─┴─:)line}─┘\n"
}

# 将IP地址由点分十进制形式转化为二进制形式
binary_ip() {
	IFS='.' read -A parts <<< $1
	for i in $(seq 1 $#parts); do
		parts[$i]=$(printf "%08d" $(echo "obase=2; $parts[$i]" | bc))
	done
	echo ${(j::)parts}
}

# 将IP地址由二进制形式转化为点分十进制形式
dot_decimal_ip() {
  echo "$((2#${1:0:8})).$((2#${1:8:8})).$((2#${1:16:8})).$((2#${1:24:8}))"
}

# 解析以CIDR表示法或掩码表示法表示的子网
# 返回：子网地址 子网前缀长度 子网掩码 子网首地址 广播地址
parse_net() {
	# 获得子网地址和子网前缀长度
	local net len
	# 如果子网为CIDR表示法
	if [[ $1 =~ "^(([0-9]+\.){3}[0-9]+)/([0-9]+)$" ]]; then
  	net="$match[1]"
		len="$match[3]"
	# 如果子网为掩码表示法
	elif [[ $1 =~ "^(([0-9]+\.){3}[0-9]+)[[:space:]]+(([0-9]+\.){3}[0-9]+)$" ]]; then
		net="$match[1]"
		len=${$(binary_ip $match[3])%%0*}
		len=$#len
	# 如果格式错误，直接返回假
	else 
		return
	fi

	# 修正子网
	net=$(binary_ip $net)
	net=$(dot_decimal_ip ${net:0:$len}$(printf "%0$((32 - len))d" 0))

	# 获得子网掩码
	local mask=$(dot_decimal_ip $(printf "1%.0s" $(seq 1 $len))$(printf "%0$((32 - len))d" 0))

	# 获得子网首地址
	local first_ip=$(binary_ip $net)
	first_ip=$(dot_decimal_ip ${first_ip:0:$len}$(printf "%0$((32 - len))d" 1))

	# 获得子网广播地址
	local last_ip=$(binary_ip $net)
	last_ip=$(dot_decimal_ip ${last_ip:0:$len}$(printf "1%.0s" $(seq 1 $((32 - len)))))

	# 返回解析结果
	echo $net $len $mask $first_ip $last_ip
}

# 检查IP是否处于子网内
# 0: 不在子网内
# 1: 为子网内普通地址
# 2: 为子网地址
# 3: 为子网首地址
# 4: 为子网末地址（广播地址）
check_ip_subnet() {
	# 获得参数
  local ip=$1
  local net=$2

	# 解析子网
	local result=($(parse_net $2))
	# 如果解析失败，直接返回0（不在子网内）
	if [[ -z $result ]]; then return 0; fi
	# 获得子网地址和子网前缀长度
	local net=$result[1]
	local len=$result[2]

	case $ip in
		# 子网地址
		$net) return 2;;
		# 子网首地址
		$result[4]) return 3;;
		# 子网末地址
		$result[5]) return 4;;
	esac

	# 将子网地址和IP地址转换为二进制
	net=$(binary_ip $net)
	ip=$(binary_ip $ip)

	# 检查IP地址前缀位和子网地址前缀位是否相同，相同则返回1（在子网内），否则范围0（不在子网内）
	[[ ${ip:0:$len} == ${net:0:$len} ]] && return 1 || return 0
}

# 检查IP地址是否合规
# 0: 违规
# 1: 合规
check_ip() {
	# 判断是否已存在
	if [[ -v clients[(r)$client_ip] ]]; then
		show "IP address [$client_ip] has been assigned." error
		return 0
	fi

	# 判断是否符合IPv4格式
	if [[ ! $client_ip =~ "^([0-9]{1,3}\.){3}[0-9]{1,3}$" ]]; then
  		show "IP address [$client_ip] is not a valid IPv4 address." error
			return 0
	fi

	# 判断是否属于子网
	check_ip_subnet $client_ip $ovpn_net
	case $? in
		0) 
			# 若不为子网内地址，报错
			show "IP address [$client_ip] is not within OpenVPN NET [$ovpn_net]." error
			return 0;;
		2)
			# 若为子网地址，报错
			show "IP address [$client_ip] cannot be the net address of OpenVPN NET [$ovpn_net]." error
			return 0;;
		3)
			# 若为子网首地址，报错
			show "IP address [$client_ip] cannot be the first address of OpenVPN NET [$ovpn_net]." error
			return 0;;
		4)
			# 若为子网末地址，报错
			show "IP address [$client_ip] cannot be the broadcast address of OpenVPN NET [$ovpn_net]." error
			return 0;;
	esac

	# 检查是否匹配OpenVPN拓扑模式
	case $ovpn_topology in
		# 若OpenVPN拓扑模式为net30
		net30)
			# 判断低8位是否模4余1
			local part=${client_ip##*.}
			if ((part % 4 != 1)); then
				show "The rightmost part of the client's IP address must be equal to n*4+1, where n is a natural number." error
				return 0
			fi;;
	esac

	return 1
}

# 检索客户信息
select_clients() {
	# 初始化客户ID数组
	typeset -ag selected_ids=()
	client_id=${client_id:-'.*'}
  client_ip=${client_ip:-'.*'}
	local data=("#" "Client ID" "IP Address" "OVPN File Path")
	for number in $(seq 1 $#clients); do
		local id=$number_ids[$number]
		local ip=$clients[$id]
		if [[ ! $id =~ $client_id ]] || [[ ! $ip =~ $client_ip ]]; then
  		continue
		fi
		selected_ids+=$id
		data+=$number
		data+=$id
		data+=$ip
		data+="${ovpn_home}client/${id}.ovpn"
	done

	# 输出检索结果
	if [[ -z $clients ]]; then
		show "There are no client accounts." info
	elif [[ -z $selected_ids ]]; then
    show "There are no client accounts that meet the specified criteria." info
	else
		table data 4
	fi
}

set_client_ip() {
	# 移除当前客户的IP配置文件
	rm -f ccd/${client_id}

	# 如果未配置IP，直接返回
	if [[ -z "$client_ip" ]]; then return; fi

	# 下一个IP地址
	local next_ip=${client_ip%.*}.$((${client_ip##*.} + 1))
	# 解析子网
	local result=($(parse_net $ovpn_net))
	# 子网掩码
	local mask=$result[3]
	# 首个IP地址
	local first_ip=$result[4]

	local part2
	# 根据OpenVPN拓扑模式，确定配置的第二部分
	case $ovpn_topology in
		# 若模式为subnet，设置为子网掩码
		subnet)
			part2=$mask;;
		# 若模式为net30，设置为client_ip的下一个IP地址
		net30)
			part2=$next_ip;;
		# 若模式为p2p，设置为子网的首个IP地址
		p2p)
			part2=$first_ip;;
	esac

	# 配置IP地址
	echo "ifconfig-push $client_ip $part2" >> ccd/${client_id}
}

# 新增客户
# 0: 新增失败
# 1: 新增成功
insert_client() {
	# 判断是否提供ID
	if [ -z "$client_id" ]; then
		show "Please provide the ID of the new client using the -c parameter." error
  	return 0
	fi

	# 判断ID是否合法
	if [[ ! $client_id =~ $sh_id_regex ]]; then
		show "The client ID can only consist of lowercase letters, numbers, and hyphens (-)." error
		return 0
	elif [[ -v clients[$client_id] ]]; then
		show "Client [$client_id] already exists." error
		return 0
	fi

	# 判断IP是否合法
	if [[ -n "$client_ip" ]]; then
		check_ip
		if ((? == 0)); then return 0; fi
	fi

	# 创建客户
	# 进入easy-rsa目录
	cd easy-rsa

	# ① 为客户创建密钥对和请求文件并签发证书
	./easyrsa build-client-full $client_id nopass > /dev/null 2>&1
	
	# 进入OpenVPN目录
	cd ..

	# ② 配置IP地址
	set_client_ip

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
$(<"$(conf $ovpn_conf ca)")
</ca>
<tls-auth>
$(egrep -v "^#" ta.key)
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
	return 1
}

# 修改客户
# 0: 修改失败
# 1: 修改成功
modify_client() {
	# 判断是否提供ID
	if [ -z "$client_id" ]; then
		show "Please provide the ID of the client you want to modify using the -c parameter." error
  	return 0
	fi
	# 判断ID是否存在
	if [[ -z clients[$client_id] ]]; then
  	show "Client [$client_id] does not exist." error
		return 0
	fi

	# 判断是否提供IP
	if [ -z "$client_ip" ]; then
		if [[ $clients[$client_id] == $undefined ]]; then
			show "Client [$client_id] is not assigned a fixed IP address." info
			return 0
		fi
		show "Do you want to delete the fixed IP address [${clients[$client_id]}] for client [$client_id]?" ask
		echo -n "Yes(y) or No: "
		read response
		if [[ ${response:l} != "y" && ${response:l} != "yes" ]]; then
    	return 0
		fi
		rm -f ${ovpn_home}ccd/${client_id}
	else
		# 判断IP是否合规
		check_ip
		if ((? == 0)); then return 0; fi

		# 配置IP地址
		set_client_ip
	fi

	# 显示结果
	show "Client [$client_id] has been successfully modified." result
	reload_clients
	select_clients

	return 1
}

# 删除客户
# 0: 删除失败
# 1: 删除成功
# 2: 取消删除
delete_clients() {
	client_id=${client_id:-'.*'}
  client_ip=${client_ip:-'.*'}
	# 收集符合删除条件的客户ID
	select_clients

	# 没有符合删除条件的客户，直接退出
	if [[ -z $selected_ids ]]; then
		return 0
	fi

	# 确认是否删除
	show "Should the above-mentioned clients be deleted?" ask
	echo -n "Yes(y) or No: "
	read response
	if [[ ${response:l} != "y" && ${response:l} != "yes" ]]; then
    return 2
	fi

	# 删除客户相关文件
	for id in $selected_ids; do
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

	return 1
}

# 获得所有客户信息
reload_clients() {
	typeset -gA clients=()
	typeset -gA id_numbers=()
	typeset -gA number_ids=()
	for file in $(ls -tr client); do
		local id=$(basename ${file%.*})
		local ip=$(conf "ccd/$id" ifconfig-push | awk '{print $1}')
		clients[$id]=${ip:-$undefined}
		id_numbers[$id]=$#clients
		number_ids[$#clients]=$id
	done
}

# 插入向导
# 0: 取消
# 1: 结束
guide_insert() {
	separator_line "Create client Account"

	# 接收客户端ID
	# 提示用户输入要创建客户端的ID
	show "Please enter the ID of the client you want to create. Press ENTER directly to cancel." ask
	while true; do
		# 接收用户输入的客户端编号
    echo -n "Client ID [Cancel]: "
		read client_id

		# 如果未输入内容，返回取消标志
		if [ -z "$client_id" ]; then return 0; fi

		# 如果ID不合法，提示错误
		if [[ ! $client_id =~ $sh_id_regex ]]; then
			show "The client ID can only consist of lowercase letters, numbers, and hyphens (-). Please enter a valid client ID." error
		elif [[ -v clients[$client_id] ]]; then
			show "Client [$client_id] already exists. Please enter a valid client ID." error
		# 如果ID合法，跳出循环
		else break
		fi
	done

	# 接收客户端IP
	# 提示用户输入要修改客户端的IP
	show "Please enter the IP address for client [$client_id].\nEnter a hyphen (-) to clear the IP config.\nPress ENTER directly to cancel." ask
	while true; do
		# 接收用户输入的IP地址
    echo -n "Client [$client_id] IP Address(#.#.#.#) [Cancel]: "
		read client_ip

		# 如果未输入内容，返回取消标志
		if [ -z "$client_ip" ]; then return 0; fi

		# 如果输入内容为-，表示取消IP地址设置，将IP地址设置为空
		if [[ $client_ip == "-" ]]; then
			client_ip=""
		fi

		# 创建客户端，成功则返回结束标志
		insert_client
		if ((? == 1)); then return 1; fi

		# 失败则提示用户重新输入IP地址
		show "Please re-enter the IP address for client [$client_id]." ask
	done
}

# 更新向导
# 0: 取消
# 1: 结束
guide_update() {
	# 显示分割线
	separator_line "Modify client IP"

	# 接收客户端编号
	# 提示用户输入要修改客户端的编号
	show "Please enter the number of the client you want to modify. Press ENTER directly to cancel." ask
	while true; do
		# 接收用户输入的客户端编号
    echo -n "Client Number(#) [Cancel]: "
		read number

		# 如果未输入内容，返回取消标志
		if [ -z "$number" ]; then return 0; fi

		# 如果用户输入正确，跳出循环
		if [[ $number =~ "^[0-9]+$" ]] && ((number > 0 && number <= $#number_ids)) then break; fi

		# 提示用户输入错误
		show "Please enter a valid client number(#∈[1,$#number_ids])." error
	done

	# 获取编号对应的客户端ID
	client_id=$number_ids[$number]

	# 接收客户端IP
	# 提示用户输入要修改客户端的IP
	show "Please enter the IP address for client [$client_id].\nEnter a hyphen (-) to clear the IP config.\nPress ENTER directly to cancel." ask
	while true; do
		# 接收用户输入的IP地址
    echo -n "Client [$client_id] IP Address(#.#.#.#) [Cancel]: "
		read client_ip

		# 如果未输入内容，返回取消标志
		if [ -z "$client_ip" ]; then return 0; fi

		# 如果输入内容为-，表示取消IP地址设置，将IP地址设置为空
		if [[ $client_ip == "-" ]]; then
			client_ip=""
		fi

		# 修改客户端，成功则返回结束标志
		modify_client
		if ((? == 1)); then return 1; fi

		# 失败则提示用户重新输入IP地址
		show "Please re-enter the IP address for client [$client_id]." ask
	done
}

# 删除向导
# 0: 取消
# 1: 结束
guide_delete() {
	# 显示分割线
	separator_line "Delete client Accounts"

	# 接收客户端编号
	# 提示用户输入要删除客户端的编号
	show "Please enter the number of the client you want to delete.\nEnter an asterisk (*) to delete all client accounts.\nPress ENTER directly to cancel." ask
	
	while true; do
		# 接收用户输入的客户端编号
    echo -n "Client Numbers(#,#-#) [Cancel]: "
		read numbers

		# 如果未输入内容，返回取消标志
		if [ -z "$numbers" ]; then return 0; fi

		# 解析编号
		client_id=""
		client_ip=""
		local parse_failed=false
		if [[ $numbers != "*" ]]; then
    	IFS=',' read -A numbers <<< "$numbers"
			for number in $numbers; do
				if [[ $number =~ "^([0-9]+)-([0-9]+)$" ]]; then
					local start=$match[1]
					local end=$match[2]
					if ((start > 0 && start <= $#number_ids && end > 0 && end <= $#number_ids)); then
						for number in $(seq $start $end); do
							client_id+=${client_id:+|}^${number_ids[$number]}$
						done
					else
						parse_failed=true
						break
					fi
				elif [[ $number =~ "^[0-9]+$" ]] && ((number > 0 && number <= $#number_ids)); then
					client_id+=${client_id:+|}^${number_ids[$number]}$
				else
					parse_failed=true
					break
				fi
			done
		fi

		# 如果输入错误，循环重新输入
		if [[ $parse_failed == true ]]; then
			# 提示用户输入错误
			show "Invalid number format or out of range. Please enter again." error
			continue
		fi

		# 删除客户端，成功则返回结束标志
		delete_clients
		case $? in
			# 若成功，返回结束标志
			1) return 1;;
			# 若取消，让用户重新输入客户端编号
			2) 
				show "Please re-enter the number of the client to be deleted." info
				continue;;
		esac

		# 失败则询问是否重新尝试，否则返回结束标志
		show "Failed to delete clients. Would you like to try again?" ask
		echo -n "Yes(y) or No: "
		read result
		if [[ ${result:l} != "y" && ${result:l} != "yes" ]]; then return 1; fi
	done
}

# 退出向导
guide_exit() { (clear && printf '\e[3J'); exit }

# 向导
guide() {
	clear && printf '\e[3J'
	usage
	separator_line "Client Accounts List"
	unset client_id client_ip
	reload_clients
	select_clients
	separator_line

	if ((EUID != 0)); then
		show "The script requires root privileges. Please execute the script again as root." error
		echo -n "Press any key to exit..."
		read -sq
		guide_exit
	fi

	echo -en "\e[32m1)\e[0m Create"
	if [[ -n $selected_ids ]]; then
		echo -en "   |   \e[32m2)\e[0m Modify   \e[32m3)\e[0m Delete"
	fi
	echo -e "   |   \e[31m0)\e[0m Exit"

	while true; do
		echo -n "Choose [Exit]: "
		read response
		case $response in
			1) guide_insert;;
			2) [[ -n $selected_ids ]] && guide_update;;
			3) [[ -n $selected_ids ]] && guide_delete;;
			0|) guide_exit;;
			*) show "The entered function number is incorrect. Please re-enter." error; continue;;
		esac

		# 若任务执行正常结束，暂停供用户查看结果
		if ((? == 1)) then
			echo -n "Press any key to continue..."
			read -sq
		fi
		break
	done

	# 再次运行向导
	guide
}

# 输出带标题的分割线
separator_line() {
	local len=80 separator=-
	local title=${1:+ ${1:0:$((len - 8))} }
	len=$((len - $#title))
	local left_len=$((len / 2))
	local right_len=$((len - left_len))
	printf "%0.s-" $(seq 1 $left_len)
	printf ${title:-''}
	printf "%0.s-" $(seq 1 $right_len)
	echo
}

# 主方法
main() {
	# 接收参数
	local mode=g
	while getopts ':hrimdgc:a:' args; do
		case $args in
			h|r|i|m|d|g) mode=$args;;
			c) client_id=$OPTARG;;
			a) client_ip=$OPTARG;;
			:) show "Option −$OPTARG requires an argument." error; usage; exit;;
    	\?) show "Invalid option: −$OPTARG." error; usage; exit;;
		esac
	done

	case $mode in; i|m|d)
		if ((EUID != 0)); then
			show "The operation requires root privileges. Please execute the script again as root." error
			exit
		fi;;
	esac

	# 获得OVPN运行命令
	ovpn_cmd=`ps axocommand | grep "openvpn " | grep -v grep`
	if [ -z "$ovpn_cmd" ]; then
		show "OpenVPN server is not running. Please start it first." error
		exit
	fi

	# 提取OVPN目录和配置文件名
	regex='--cd (.*) --config (.*)'
	if [[ $ovpn_cmd =~ $regex ]]; then
		ovpn_home="$match[1]"
		ovpn_conf="$match[2]"
	else
		show "Failed to retrieve OpenVPN home and CONF file name." error
		exit
	fi

	# 判断OVPN目录是否存在
	if [ ! -d "$ovpn_home" ]; then
		show "The OpenVPN HOME does not exist: $ovpn_home" error
		exit
	fi

	# 进入OVPN目录
	cd $ovpn_home

	# 判断OVPN配置文件是否存在
	if [ ! -f "$ovpn_conf" ]; then
		show "The OpenVPN CONF file does not exist: $ovpn_conf" error
		exit
	fi

	# 获取服务器公网IP
	ovpn_ip=$(curl -s https://api.ipify.org)
	# 获取OVPN服务端口号
	ovpn_port=$(conf $ovpn_conf port)
	# 获取OVPN子网
	ovpn_net=$(conf $ovpn_conf server)
	# 获取OVPN拓扑模式
	ovpn_topology=$(conf $ovpn_conf topology net30)

	# 若client目录不存在，创建之
	mkdir -p client
	# 获得所有客户信息
	reload_clients

	case $mode in
		h) usage; exit;;
		r) select_clients;;
		i) insert_client;;
		m) modify_client;;
		d) delete_clients;;
		g) guide;;
	esac
}
main "$@"