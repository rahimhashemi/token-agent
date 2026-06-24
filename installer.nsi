; ============================================================
; BankMellat ePass Token Agent — NSIS Installer Script
; Build: makensis installer.nsi
; Requires: NSIS 3.x + AccessControl plugin
; ============================================================

!define PRODUCT_NAME      "BankMellat Token Agent"
!define PRODUCT_VERSION   "1.0.0"
!define PUBLISHER         "Bank Mellat"
!define INSTALL_DIR       "$PROGRAMFILES64\BankMellat\TokenAgent"
!define SERVICE_NAME      "BankMellatTokenAgent"
!define JAR_NAME          "token-agent-1.0.0.jar"
!define CA_CERT           "bankmellat-ca.crt"
!define AGENT_PORT        "7070"

; Installer settings
Name "${PRODUCT_NAME} ${PRODUCT_VERSION}"
OutFile "BankMellatTokenAgentSetup.exe"
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel admin         ; Needs admin for cert store + service
ShowInstDetails show
Unicode True

; ── Pages ────────────────────────────────────────────────────────────────
Page license
Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

LicenseData "resources\LICENSE.rtf"

; ── Main Install Section ─────────────────────────────────────────────────
Section "Core" SEC_CORE
  SectionIn RO                      ; Required, cannot be deselected

  SetOutPath "${INSTALL_DIR}"

  ; Copy the fat JAR
  File "resources\${JAR_NAME}"

  ; Copy the CA certificate (will be installed into trust store)
  File "resources\cert\${CA_CERT}"

  ; Copy bundled JRE (so users don't need Java installed)
  File /r "resources\jre21"

  ; ── Step 1: Install Root CA into Windows Certificate Store ──────────
  ; This makes Chrome and Edge trust our localhost HTTPS cert
  DetailPrint "Installing BankMellat Root CA into Windows trust store..."
  ExecWait 'certutil.exe -addstore -f "ROOT" "${INSTALL_DIR}\${CA_CERT}"' $0
  ${If} $0 != 0
    MessageBox MB_ICONEXCLAMATION \
      "Warning: Could not install Root CA automatically.$\nPlease run as Administrator."
  ${EndIf}

  ; ── Step 2: Install CA into Firefox trust store (if Firefox installed) ──
  DetailPrint "Checking for Firefox..."
  ReadRegStr $R0 HKLM \
    "SOFTWARE\Mozilla\Mozilla Firefox" "CurrentVersion"
  ${If} $R0 != ""
    DetailPrint "Firefox found — installing CA via policy..."
    ; Firefox respects Windows enterprise policies
    WriteRegStr HKLM \
      "SOFTWARE\Policies\Mozilla\Firefox\Certificates" \
      "ImportEnterpriseRoots" "true"
    ; Alternatively, copy CA to Firefox profile — see firefox-ca-install.ps1
    ExecWait 'powershell.exe -ExecutionPolicy Bypass -File \
      "${INSTALL_DIR}\scripts\firefox-ca-install.ps1"'
  ${EndIf}

  ; ── Step 3: Register as Windows Service ──────────────────────────────
  DetailPrint "Registering Windows service..."
  ExecWait '"${INSTALL_DIR}\jre21\bin\java.exe" \
    -jar "${INSTALL_DIR}\${JAR_NAME}" \
    --spring.config.location="${INSTALL_DIR}\application.yml" \
    --install-service' $0

  ; Fallback: use sc.exe to register the service wrapper
  ExecWait 'sc.exe create "${SERVICE_NAME}" \
    binPath= "${INSTALL_DIR}\jre21\bin\java.exe \
      -jar ${INSTALL_DIR}\${JAR_NAME}" \
    start= auto \
    DisplayName= "${PRODUCT_NAME}"'

  ExecWait 'sc.exe description "${SERVICE_NAME}" \
    "Bank Mellat ePass Token Agent — provides PKCS#11 access on localhost:${AGENT_PORT}"'

  ; Start the service
  ExecWait 'sc.exe start "${SERVICE_NAME}"'

  ; ── Step 4: Write registry keys for Add/Remove Programs ──────────────
  WriteRegStr HKLM \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SERVICE_NAME}" \
    "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SERVICE_NAME}" \
    "UninstallString" "${INSTALL_DIR}\uninstall.exe"
  WriteRegStr HKLM \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SERVICE_NAME}" \
    "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SERVICE_NAME}" \
    "DisplayVersion" "${PRODUCT_VERSION}"

  ; Write uninstaller
  WriteUninstaller "${INSTALL_DIR}\uninstall.exe"

  DetailPrint "Installation complete. Agent running on https://localhost:${AGENT_PORT}"
SectionEnd

; ── Uninstaller ──────────────────────────────────────────────────────────
Section "Uninstall"
  ; Stop and remove service
  ExecWait 'sc.exe stop "${SERVICE_NAME}"'
  ExecWait 'sc.exe delete "${SERVICE_NAME}"'

  ; Remove Root CA from Windows store
  ExecWait 'certutil.exe -delstore "ROOT" "BankMellat Token Agent CA"'

  ; Remove Firefox policy
  DeleteRegKey HKLM "SOFTWARE\Policies\Mozilla\Firefox\Certificates"

  ; Remove files
  RMDir /r "${INSTALL_DIR}"

  ; Remove registry
  DeleteRegKey HKLM \
    "Software\Microsoft\Windows\CurrentVersion\Uninstall\${SERVICE_NAME}"
SectionEnd
