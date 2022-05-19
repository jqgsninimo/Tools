#!/bin/zsh

# 在发生错误时提供使用方法并停止执行
usage() { echo "Usage: ${0##*/} <IPA File Path>" 1>&2; exit 1; }

# 如果用户未传入路径或传入路径并不指向IPA压缩包，提供使用方法并停止执行
if [ $# != 1 ]; then
	usage
fi
if [ "${1:e:l}" != "ipa" ]; then
	usage
fi

# 在tmp目录下创建临时目录
tmpDir="/tmp/ipa_reader_`date '+%s'`"

# 解压指定的IPA压缩包到临时目录中，qq参数使压缩过程保持静默
unzip -qq $1 -d $tmpDir

# 定义要提取的应用信息项目：[显示名称:]<文件路径>#<项目键名>
# 显示名称可不指定，这种情况下，将项目键名作为项目的显示名称
items=(
	描述文件名称:embedded.mobileprovision#Name
	团队名称:embedded.mobileprovision#TeamName
	应用ID名称:embedded.mobileprovision#AppIDName
	应用ID:embedded.mobileprovision#application-identifier
	embedded.mobileprovision#UUID
	生存日数:embedded.mobileprovision#TimeToLive
	创建时间:embedded.mobileprovision#CreationDate
	截止时间:embedded.mobileprovision#ExpirationDate
	应用名称:Info.plist#CFBundleName
	编译版本:Info.plist#CFBundleVersion
	应用版本:Info.plist#CFBundleShortVersionString)

# 循环提取每项应用信息到临时输出文件out中
for item in $items; do
	# 使用参数扩展标志s以字符:和#将项目定义字符串拆分为三部分
	parts=(${(s[#])item/:/#})
	# 若未定义显示名称，将项目键名作为显示名称
	if [ ${#parts[@]} = 2 ]; then
		parts=($parts[2] $parts[@])
	fi
	# 提取信息
	# 首先使用grep命令从相应文件中提取键名和键值行
	# 然后使用sed命令显示键值
	value=$(grep -a -A 1 ">$parts[3]<" $tmpDir/Payload/*.app/$parts[2] | sed -n -r '2s/.*>(.*)<.*/\1/p')
	# 对于一些info文件，不能直接提取信息，换用专门的defaults命令提取
	if [ ! $value ]; then
		value=$(defaults read $tmpDir/Payload/*.app/$parts[2] $parts[3])
	fi
	# 将项目的显示名称和键值追加到临时输出文件out中
	echo -e "$parts[1]#| $value" >> $tmpDir/out
done
# 使用column命令格式化输出内容，并使用sed命令实现显示名称的右对齐，输出到屏幕上
cat $tmpDir/out | column -ts '|' | sed -re 's/(.*)#( +)/\2\1: /'

# 删除临时目录
rm -rf $tmpDir