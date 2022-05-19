# ipaReader
## IPA 包信息提取工具

通过 in-house 发布的 iOS App（企业内部专有 App）会被封装为 IPA 包。
   
很多时候通过 IPA 包查看 App 的信息，如：`应用ID`｜`截止日期`｜`版本` 等，还需要先解压包，再找到相关文件，使用相应命令提取这些信息，很不方便。
   
于是实现了工具 `ipaReader`，直接传入 IPA 包文件路径，即可查看 App 的相关信息。

## 可提取信息
- 描述文件名称：`embedded.mobileprovision` → `Name`
- 团队名称：`embedded.mobileprovision` → `TeamName`
- 应用ID名称：`embedded.mobileprovision` → `AppIDName`
- 应用ID：`embedded.mobileprovision` → `application-identifier`
- UUID：`embedded.mobileprovision` → `UUID`
- 生存日数：`embedded.mobileprovision` → `TimeToLive`
- 创建时间：`embedded.mobileprovision` → `CreationDate`
- 截止时间：`embedded.mobileprovision` → `ExpirationDate`
- 应用名称：`Info.plist` → `CFBundleName`
- 编译版本：`Info.plist` → `CFBundleVersion`
- 应用版本：`Info.plist` → `CFBundleShortVersionString`

## [最新版发布页](https://github.com/jqgsninimo/Tools/releases/tag/v1.0.0)

## 使用方法
```
ipaReader <IPA File Path>
```

## 运行示例
```
% ipaReader ~/Desktop/DemoApp.ipa
   描述文件名称: DemoAppInHouseProfile
       团队名称: Appleg Ltd.
     应用ID名称: DemoAppInHouseAppID
         应用ID: XXXXXXXXXX.ltd.appleg.DemoApp
           UUID: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
       生存日数: 365
       创建时间: 2022-05-19T10:45:59Z
       截止时间: 2023-05-19T10:45:59Z
       应用名称: DemoApp
       编译版本: 1
       应用版本: 1.0.0      
```

