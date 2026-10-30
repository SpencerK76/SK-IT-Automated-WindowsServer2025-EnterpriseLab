<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage>
             <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-GB</InputLocale>
            <SystemLocale>en-GB</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UILanguageFallback>en-US</UILanguageFallback>
            <UserLocale>en-GB</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <!-- 1. System Partition (EFI) -->
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Type>EFI</Type>
                            <Size>260</Size>
                        </CreatePartition>
                        <!-- 2. Microsoft Reserved (MSR) -->
                        <CreatePartition wcm:action="add">
                            <Order>2</Order>
                            <Type>MSR</Type>
                            <Size>16</Size>
                        </CreatePartition>
                        <!-- 3. Primary Windows OS (Fixed size, not extended) -->
                        <CreatePartition wcm:action="add">
                            <Order>3</Order>
                            <Type>Primary</Type>
                            <Size>58000</Size>
                        </CreatePartition>
                        <!-- 4. Windows Recovery (WinRE) (Takes remainder, ~1-2GB) -->
                        <CreatePartition wcm:action="add">
                            <Order>4</Order>
                            <Type>Primary</Type>
                            <Extend>true</Extend>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <!-- Modify EFI -->
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Label>System</Label>
                            <Format>FAT32</Format>
                        </ModifyPartition>
                        <!-- Modify MSR -->
                        <ModifyPartition wcm:action="add">
                            <Order>2</Order>
                            <PartitionID>2</PartitionID>
                        </ModifyPartition>
                        <!-- Modify Windows OS -->
                        <ModifyPartition wcm:action="add">
                            <Order>3</Order>
                            <PartitionID>3</PartitionID>
                            <Label>Windows</Label>
                            <Format>NTFS</Format>
                            <Letter>C</Letter>
                        </ModifyPartition>
                        <!-- Modify WinRE placed final position to allow for updates -->
                        <ModifyPartition wcm:action="add">
                            <Order>4</Order>
                            <PartitionID>4</PartitionID>
                            <Label>WinRE</Label>
                            <Format>NTFS</Format>
                            <TypeID>de94bba4-06d1-4d40-a16a-bfd50179d6ac</TypeID> <!--Hides WinRE partition from Exploer -->
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/NAME</Key>
                            <Value>Windows 11 Enterprise Evaluation</Value>
                        </MetaData>
                    </InstallFrom>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>3</PartitionID>
                    </InstallTo>
                    <WillShowUI>Never</WillShowUI>
                </OSImage>
            </ImageInstall>
            <UserData>
                <AcceptEula>true</AcceptEula>
                <FullName>Admin</FullName>
                <Organization>SKAutomation</Organization>
            </UserData>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <UILanguage>en-GB</UILanguage>
            <InputLocale>en-GB</InputLocale>
            <SystemLocale>en-GB</SystemLocale>
            <UserLocale>en-GB</UserLocale>
            <UILanguageFallback>en-GB</UILanguageFallback>
        </component>
                <component name="Microsoft-Windows-IE-ESC" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <IEHardenAdmin>false</IEHardenAdmin>
            <IEHardenUser>true</IEHardenUser>
        </component>
        <component name="Microsoft-Windows-Security-SPP-UX" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SkipAutoActivation>true</SkipAutoActivation>
        </component>
        <component name="Microsoft-Windows-ServerManager-SvrMgrNc" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DoNotOpenServerManagerAtLogon>true</DoNotOpenServerManagerAtLogon>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>Win25GoldenImg</ComputerName>
            <TimeZone>GMT Standard Time</TimeZone>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>en-GB</InputLocale>
            <SystemLocale>en-GB</SystemLocale>
            <UILanguage>en-GB</UILanguage>
            <UserLocale>en-GB</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <AutoLogon>
                <Password>
                    <Value>${admin_password}</Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <LogonCount>2</LogonCount>
                <Username>${admin_username}</Username>
            </AutoLogon>
<FirstLogonCommands>
    <SynchronousCommand wcm:action="add">
        <Order>1</Order>
        <CommandLine>powershell.exe -ExecutionPolicy Bypass -Command "Get-NetAdapter | Where-Object Status -eq 'Up' | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue"</CommandLine>
        <Description>Set Network Category to Private</Description>
        <RequiresUserInput>false</RequiresUserInput>
    </SynchronousCommand>
    <SynchronousCommand wcm:action="add">
        <Order>2</Order>
        <CommandLine>powershell.exe -ExecutionPolicy Bypass -Command "Set-LocalUser -Name 'Administrator' -PasswordNeverExpires $true"</CommandLine>
        <Description>Set Administrator Password to Never Expire</Description>
        <RequiresUserInput>false</RequiresUserInput>
    </SynchronousCommand>
    <SynchronousCommand wcm:action="add">
        <Order>3</Order>
        <CommandLine>powershell.exe -ExecutionPolicy Bypass -Command "$vol = (Get-Volume | Where-Object { $_.FileSystemLabel -eq 'OEMDRV' -or (Test-Path ($_.DriveLetter + ':\bootstrap-winrm-https.ps1')) }).DriveLetter; if ($vol) { &amp; ($vol + ':\bootstrap-winrm-https.ps1') } else { Get-Volume | Out-File C:\bootstrap_error.txt }"</CommandLine>
        <Description>Locate and Execute HTTPS WinRM Bootstrap</Description>
        <RequiresUserInput>false</RequiresUserInput>
    </SynchronousCommand>
</FirstLogonCommands>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>${admin_password}</Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
            </UserAccounts>
        </component>
    </settings>
    <settings pass="offlineServicing">
        <component name="Microsoft-Windows-LUA-Settings" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <EnableLUA>true</EnableLUA>
        </component>
    </settings>
    <cpi:offlineImage cpi:source="wim:p:/packer~ws2025/labautomation/install_wim/install.wim#Windows Server 2025 SERVERDATACENTER" xmlns:cpi="urn:schemas-microsoft-com:cpi" />
</unattend>
