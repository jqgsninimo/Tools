# multiWar
## 多服务器 WAR 包生成工具

该脚本会在 WAR 包 cs001.war 和 em001.war 的基础上，生成编号从 002 开始的一系列服务器 WAR 包。

具体说明参考文档：[多服务器 WAR 包生成脚本](https://www.notion.so/jqgsninimo/WAR-b26fcfac9ce848b89468801395655420?pvs=4)

## [1.0版发布页](https://github.com/jqgsninimo/Tools/releases/tag/v1.0.1)

## 使用方法
```
multiWar.sh [warPath] [indexRange]
```
- `warPath`：WAR 包目录
    
    指定目录下应包含 WAR 包 `cs001.war` 和 `em001.war`。
    
    默认值为批处理文件所处目录。
    
    也即当 WAR 包文件与批处理文件 `multiWar.sh` 处于同一目录下时，可省略该参数。
    
- `indexRange`：生成 WAR 包索引范围
    
    设定值的格式为：`[<startIndex>-]<endIndex>`。
    
    其中 `startIndex` 和 `endIndex` 为大于1的正整数，且 `startIndex` 不大于 `endIndex`。
    
    如格式所示，可省略 `startIndex`，仅指定一个表示 `endIndex` 的数字，此时 `startIndex` 取默认值 `2`。
    
    默认值为 `2-3`，也即 `startIndex=2`、`endIndex=3`，表示需生成序号为 `002` 和 `003` 的服务器 WAR 包。
    
    - 示例
        | indexRange 值 | 生成 WAR 包序号 |
        | --- | --- |
        | 默认 | 002 003 |
        | 3-5 | 003 004 005 |
        | 4 | 002 003 004 |
        | 5-5 | 005 |