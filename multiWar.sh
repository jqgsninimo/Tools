#!/bin/sh

# 设置WAR包目录参数默认值为批处理文件所处目录
path=`dirname $0`
# 设置生成WAR包索引范围参数默认值
indexRange="2-3"

# 如果只有1个参数，将该参数作为索引范围处理
# 如果有2个参数，第一个参数作为WAR包目录处理，第二个参数作为索引范围处理
if [ $# -eq 1 ]; then
  indexRange=$1
elif [ $# -eq 2 ]; then
  path=`dirname $1`
  indexRange=$2
fi

# 以减号-作为分隔符拆分索引范围参数，各个部分组成数组indexes
indexes=($(echo $indexRange | awk -F'-' '{for(i=1; i<=NF; i++) print $i}'))
# 如果只有一个数字，将该数字作为endIndex，生成序列[2,endIndex]，存储到indexes中
# 如果多于一个数字，将首个数字作为startIndex，第二个数字作为endIndex，生成序列[startIndex,endIndex]，存储到indexes中
if [ ${#indexes[@]} -eq 1 ]; then
  indexes=`seq 2 ${indexes[0]}`
else
  indexes=`seq ${indexes[0]} ${indexes[1]}`
fi

# 进入WAR包目录
cd $path

# 设置需处理的文件数组
files="\
WEB-INF/classes/system.properties \
WEB-INF/classes/log4j.properties \
WEB-INF/classes/spring/smartHomeService.xml \
WEB-INF/classes/applicationContext.xml"
jarFile=WEB-INF/lib/MLOne-dao-1.5.jar
urlFile=url.properties

# 根据索引序列生成对应的WAR包
for index in $indexes; do
  # 将当前索引值格式化为前置0的三位数字后缀
  suffix=`printf '%03d' $index`
  # 以1号WAR包为模版生成当前索引所对应的WAR包
  cp cs001.war cs${suffix}.war
  cp em001.war em${suffix}.war
  # 修改生成WAR包中需处理的文件，将001替换为当前索引所对应的后缀
  for warFile in {cs,em}${suffix}.war; do
    for i in $files $jarFile; do
        jar xf $warFile $i
    done
    jar xf $jarFile $urlFile

    for i in $files $urlFile; do
        sed -i "" "s#cs001#cs${suffix}#" $i
        sed -i "" "s#em001#em${suffix}#" $i        
        sed -i "" "s#fssadmin001#fssadmin${suffix}#" $i
    done

    jar uf $jarFile $urlFile
    for i in $files $jarFile; do
        jar uf $warFile $i
    done

    rm -f $urlFile
    rm -fr WEB-INF
  done
done