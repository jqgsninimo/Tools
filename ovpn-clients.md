# ovpn-clients
## OpenVPN 客户端账号管理工具

该脚本提供了 OpenVPN 客户端账号的的增删改查功能。

具体说明参考文档：[OpenVPN 客户端账号管理脚本](https://www.notion.so/jqgsninimo/WAR-b26fcfac9ce848b89468801395655420?pvs=4)

## [1.0版发布页](https://github.com/jqgsninimo/Tools/releases/tag/v1.0.2)

## 使用方法
```
ovpn-clients -hrimd [-c <clientId>] [-a <ipAddress>]
```
- `h`：显示工具说明。
- `r`：显示 ID 匹配 `clientId` 且 IP 地址匹配 `ipAddress` 的客户端账号信息。

    账号信息包括：ID、固定 IP 地址和 OVPN 文件路径。

    `clientId` 和 `ipAddress` 作为正则表达式处理，不设置则按全部匹配处理。
    
- `i`：创建 ID 为 `clientId` 的客户端账号，并设置其固定 IP 地址为 `ipAddress`。

    必须指定 `clientId`，且不能与现有 ID 重复。

    若不指定 `ipAddress`，则不设置该账号的固定 IP 地址。

- `m`：修改 ID 为 `clientId` 的客户端账号的固定 IP 地址为 `ipAddress`。

    必须指定 `clientId`。

    若未指定 `ipAddress`，则清除该账号的固定 IP 地址。

- `d`： ID 匹配 `clientId` 且 IP 地址匹配 `ipAddress` 的客户端账号。
    
    `clientId` 和 `ipAddress` 作为正则表达式处理，不设置则按全部匹配处理。

## 用法演示
![用法演示](https://github.com/jqgsninimo/Tools/blob/main/ovpn-clients-demo.jpg)