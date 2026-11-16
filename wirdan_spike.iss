; مثبّت اختبار الجدوى — Inno Setup 6
; يُستدعى من GitHub Actions: ISCC.exe /DSourceDir=<مجلد Release> installer\wirdan_spike.iss

#define MyAppName "WIRDAN Spike"
#define MyAppVersion "0.0.1"
#define MyAppExe "wirdan_spike.exe"

#ifndef SourceDir
  #error "مرّر /DSourceDir=<مجلد بناء Release>"
#endif

[Setup]
AppId={{67F3475F-081B-49D5-AFF2-C4461DDCB422}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=WIRDAN
; تثبيت لكل مستخدم بدون صلاحيات Administrator
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=WIRDAN-Spike-Setup
SetupIconFile=..\branding\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; إغلاق البرنامج تلقائياً إن كان يعمل أثناء التثبيت/الإزالة
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "إنشاء اختصار على سطح المكتب / Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "تشغيل {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
// عند الإزالة: نحذف مدخل التشغيل التلقائي من سجل المستخدم إن وُجد.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
    RegDeleteValue(HKEY_CURRENT_USER,
      'Software\Microsoft\Windows\CurrentVersion\Run', 'WIRDAN Spike');
end;
