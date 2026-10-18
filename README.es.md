# VMware Community Toolkit

[English](README.md)

Utilidades PowerShell para inventariar vSphere, observar la configuración de ESXi, informar sobre snapshots y datastores, analizar exportaciones VCF offline, comparar inventarios y generar informes HTML portables. Proyecto comunitario independiente, sin afiliación con VMware ni Broadcom.

Los lectores en vivo requieren una **conexión PowerCLI explícita y autorizada**. La comparación, los analizadores VCF y el generador HTML funcionan sin conexión VMware. Las observaciones de configuración no certifican seguridad ni cumplimiento. La falta de evidencia se mantiene como Unknown; un resultado vacío no acredita visibilidad completa.

**MIT — Copyright (c) 2026 Daniel Fuentes.** Consulta [LICENSE](LICENSE) y la [procedencia](PROVENANCE.md). Este es el candidato local `v0.1.0-rc5`; no se ha creado una URL pública ni una release. Conserva toda la estructura de directorios. [Instalación y primer uso](docs/GETTING-STARTED.md) · [Compatibilidad](docs/COMPATIBILITY.md) · [Ejemplos](examples/README.md).

## Empezar sin infraestructura

Desde la raíz de la copia completa, con una sesión PowerShell ya disponible. No hace falta PowerCLI, Pester, credenciales ni acceso a la red:

```powershell
./scripts/Invoke-VMwareToolkit.ps1 -ListProfiles
./scripts/Invoke-VMwareToolkit.ps1 -ListChecks
$demoPath = Join-Path ([IO.Path]::GetTempPath()) ('vmware-toolkit-demo-' + [guid]::NewGuid().ToString('N') + '.html')
$demo = ./examples/Invoke-CommunityOfflineDemo.ps1 -OutputPath $demoPath
$demo.Inventory | Select-Object VM, PowerState, NumCpu, MemoryGB
$demo.Snapshots | Select-Object VM, Snapshot, Created, SizeGB
$demo.EsxiAudit.HostSecurity
$demo.Changes
$demo.VCF.OperationsAlerts
$demo.Report
```

La demostración carga **modelos de salida ficticios** de inventario, snapshots y configuración ESXi; no ejecuta sus consultas PowerCLI. Sí ejecuta localmente la comparación, los siete analizadores VCF y el generador HTML con esos fixtures. Crea un HTML nuevo y cinco observaciones de comparación, sin cambiar infraestructura. La ruta temporal del ejemplo sirve para datos ficticios; las evidencias reales deben guardarse en un directorio aprobado y restringido fuera de Git. No se sobrescriben archivos existentes. Hay comandos individuales en [ejemplos](examples/README.md).

## Herramientas disponibles

Se incluyen 25 herramientas del toolkit y un ejecutor auxiliar de laboratorio. Conserva `scripts/Private` y el resto de la copia junto a los scripts. Consulta cada contrato con `Get-Help ./scripts/<category>/<tool>.ps1 -Full`.

### Informes de máquinas virtuales

| Herramienta | Función y límite |
|---|---|
| [Get-VMInventory.ps1](scripts/Reporting/Get-VMInventory.ps1) | Identidad, estado, CPU, memoria y host de las VM |
| [Get-VMwareToolsStatus.ps1](scripts/Reporting/Get-VMwareToolsStatus.ps1) | Versión y estado de VMware Tools conocidos por el servidor |
| [Get-SnapshotReport.ps1](scripts/Reporting/Get-SnapshotReport.ps1) | Identidad, fecha de creación y tamaño de snapshots |
| [Get-OldSnapshots.ps1](scripts/Reporting/Get-OldSnapshots.ps1) | Snapshots que superan una antigüedad; sin eliminarlos |
| [Get-VMHostDnsReport.ps1](scripts/Reporting/Get-VMHostDnsReport.ps1) | Servidores DNS, dominio y sufijos de búsqueda |

### Observaciones de hosts y almacenamiento

| Herramienta | Función y límite |
|---|---|
| [Get-VMHostHealth.ps1](scripts/Health/Get-VMHostHealth.ps1) | Resumen de alarmas y conexión del host; no certifica el hardware |
| [Get-DatastoreCapacity.ps1](scripts/Storage/Get-DatastoreCapacity.ps1) | Capacidad y espacio libre/usado en GiB de datastores accesibles |

### Observaciones de configuración y seguridad ESXi

| Herramienta | Función y límite |
|---|---|
| [Get-VMHostSecurityConfiguration.ps1](scripts/Security/Get-VMHostSecurityConfiguration.ps1) | Modo lockdown y configuración de servicios declarados |
| [Get-VMHostFirewallReport.ps1](scripts/Network/Get-VMHostFirewallReport.ps1) | Excepciones de firewall y puertos/protocolos declarados |
| [Get-VMHostSyslogConfiguration.ps1](scripts/Logging/Get-VMHostSyslogConfiguration.ps1) | Cinco ajustes syslog revisados; no comprueba la entrega |
| [Get-VMHostTimeConfiguration.ps1](scripts/Network/Get-VMHostTimeConfiguration.ps1) | Configuración NTP y datos opcionales del servicio de hora |
| [Get-VMHostAdvancedSettings.ps1](scripts/Security/Get-VMHostAdvancedSettings.ps1) | Claves concretas; los valores ajenos al perfil se ocultan |
| [Get-VMHostNtpConfiguration.ps1](scripts/Network/Get-VMHostNtpConfiguration.ps1) | Servidores NTP configurados; no verifica sincronización |
| [Get-VMCertificateExpiry.ps1](scripts/Security/Get-VMCertificateExpiry.ps1) | Fechas de certificados SSL de máquina; no verifica confianza |

### Informes y comparación offline

| Herramienta | Función y límite |
|---|---|
| [New-vSphereHealthReport.ps1](scripts/Reporting/New-vSphereHealthReport.ps1) | HTML local portable desde datos estructurados, con secciones ESXi/VCF opcionales |
| [Compare-vSphereInventory.ps1](scripts/Reporting/Compare-vSphereInventory.ps1) | Altas/bajas de VM y cambios de CPU, memoria y estado dentro de un ámbito |

### Análisis experimental de VCF offline

| Herramienta | Función y límite |
|---|---|
| [Get-VCFInventory.ps1](scripts/VCF/Get-VCFInventory.ps1) | Inventario de dominios y estados operativos de SDDC Manager |
| [Get-VCFHealth.ps1](scripts/VCF/Get-VCFHealth.ps1) | Estados históricos de tareas SoS; salud actual Unknown |
| [Get-VCFVersions.ps1](scripts/VCF/Get-VCFVersions.ps1) | Versiones de SDDC Manager; no representa toda la BOM de VCF |
| [Get-VCFCertificates.ps1](scripts/VCF/Get-VCFCertificates.ps1) | Caducidad declarada de certificados y errores de recuperación |
| [Get-VCFLifecycleStatus.ps1](scripts/VCF/Get-VCFLifecycleStatus.ps1) | Estados de actualización del dominio y recursos completados/totales |
| [Get-VCFOperationsAlerts.ps1](scripts/VCF/Get-VCFOperationsAlerts.ps1) | Páginas completas de alertas de Operations; tiempos sin unidad confirmada |
| [Get-VCFLicensingReport.ps1](scripts/VCF/Get-VCFLicensingReport.ps1) | Un objeto SYSTEM LicensingInfo; distingue registro y suscripción |

### Ejecución y vista previa protegida

| Herramienta | Función y límite |
|---|---|
| [Invoke-VMwareToolkit.ps1](scripts/Invoke-VMwareToolkit.ps1) | Perfiles de lectura fijos, resultados estructurados y HTML opcional |
| [Set-VMHostDnsServers.ps1](scripts/Network/Set-VMHostDnsServers.ps1) | Limitado a WhatIf; bloquea cambios DNS y queda fuera del ejecutor central |
| [Invoke-ToolkitLabValidation.ps1](scripts/Lab/Invoke-ToolkitLabValidation.ps1) | Preflight auxiliar offline; Connect requiere autorización expresa aparte |

## Ejecutor central

[Invoke-VMwareToolkit](docs/CENTRAL-RUNNER.md) ejecuta secuencialmente 14 comprobaciones de lectura predefinidas. Las opciones offline `-ListProfiles` y `-ListChecks` no consultan VMware. Para ejecutar comprobaciones exige una conexión existente en `-Server`, la declaración `-EndpointType` y un identificador opaco `-ScopeId`; no inicia sesión ni acepta rutas arbitrarias de scripts o credenciales. Se elige un perfil **o** `-Checks`, nunca ambos.

| Perfil | Comprobaciones |
|---|---|
| Inventory | VMInventory, Tools, Datastores |
| Operations | VMInventory, Tools, Snapshots, OldSnapshots, Datastores, HostHealth, Dns, Ntp, Time |
| Security | Certificates, HostSecurity, Firewall, Syslog, Time, AdvancedSettings |
| All | VMInventory, Tools, Snapshots, OldSnapshots, Datastores, HostHealth, Dns, Ntp, Certificates, HostSecurity, Firewall, Syslog, Time, AdvancedSettings |

Admite filtros VMName, VMHostName, DatastoreName, RuleName y claves exactas SettingName. Reutiliza consultas de snapshots, hora y ajustes cuando es posible, y limita las filas retenidas. Esos límites no acotan los buffers internos del proveedor, el número de llamadas API ni la duración. Por defecto detiene el trabajo nuevo tras un fallo; ContinueOnError permite continuar con comprobaciones independientes.

State utiliza **Success, Failed, Unknown y NotRun**, conservando Status/Reason y el Outcome global anteriores. Una ejecución vacía completada no demuestra visibilidad completa. PartialFailure se presenta como State=Failed: revisa ExecutionCompleted, Report y los estados individuales. Los fallos estructurados no siempre generan una excepción terminante. WhatIf solo evita crear el HTML solicitado: las consultas de lectura siguen ejecutándose.

La siguiente sintaxis es **exclusivamente para un futuro laboratorio autorizado**, no para ejecución offline. `$connection` debe contener una conexión explícita autorizada aparte y con TLS estricto; `$newPrivateHtmlPath` debe ser un archivo nuevo en un directorio restringido ya existente:

```powershell
$result = ./scripts/Invoke-VMwareToolkit.ps1 -Server $connection -EndpointType vCenter -ScopeId 'authorized-lab-scope' -Profile Inventory -VMName 'lab-*'
$result.Checks | Select-Object Check, Requested, Status, State, RowCount, Message
$result = ./scripts/Invoke-VMwareToolkit.ps1 -Server $connection -EndpointType vCenter -ScopeId 'authorized-lab-scope' -Checks VMInventory,Tools,Snapshots -VMName 'lab-*' -HtmlPath $newPrivateHtmlPath
if (-not $result.ExecutionCompleted) { throw 'Execution incomplete; inspect sanitized statuses privately.' }
```

Sigue la [guía de primera sesión autorizada con vCenter](docs/VCENTER-FIRST-RUN.md) antes de acceder. Se necesitan los permisos de lectura de todas las comprobaciones elegidas; los roles mínimos exactos aún no están verificados. El tamaño de snapshots puede requerir Datastore.Browse. ESXi directo tiene un ámbito de inventario y políticas distinto; allí se bloquea expresamente la consulta de certificados. Una consulta correcta no garantiza visibilidad completa. La vista previa DNS queda fuera de todos los perfiles y los cambios DNS reales siguen bloqueados.

## Demostración HTML

[Abrir informe ficticio portable](docs/demo/community-report.html) · [PNG de escritorio](docs/demo/community-desktop.png) · [PNG de ventana estrecha](docs/demo/community-narrow.png) · [procedencia y reproducción de capturas](docs/demo/README.md)

![Informe ficticio renderizado localmente; no es una captura de un entorno VMware](docs/demo/community-desktop.png)

El informe ofrece recuentos de disponibilidad, navegación por secciones, tablas adaptables con desplazamiento y datos opcionales de ejecución, ESXi y VCF. Escapa HTML, utiliza CSP, no incorpora JavaScript/CDN/telemetría y rechaza sobrescrituras. Una colección o un campo ausente se muestra como Unknown; un array vacío significa que no se han aportado registros. La disponibilidad de datos no acredita salud ni cumplimiento. Las secciones VCF mantienen separadas las fuentes SDDC Manager, Operations y vCenter. Las capturas muestran fixtures inventados, no la interfaz VMware ni un entorno real. [Esquema y límites](docs/UNIFIED-REPORTING.md).

## Requisitos e instalación

| Uso | Dependencias necesarias |
|---|---|
| Demo offline, HTML, comparación y procesamiento JSON VCF | PowerShell existente; sin PowerCLI, cuenta ni red |
| Lectores vSphere/ESXi en vivo | VMware.VimAutomation.Core oficial y dependencias, TLS de confianza, conexión explícita autorizada y permisos de lectura suficientes |
| Pruebas de desarrollo | Pester 6.2.0, PSScriptAnalyzer 1.25.0, Python 3.9+ estándar y Git para una prueba con repositorio temporal |
| Verificación de distribución | Python 3.9+ estándar; sin Git, módulos ni red |

PowerShell 7.4+ es el objetivo del código; **7.6.7/Linux x64 es el entorno ejecutado localmente**. No se han verificado otras versiones de PowerShell, Windows/macOS ni gran escala. Se ejecutó Python 3.14.7; el código estándar apunta a 3.9+. No se incluyen runtimes ni módulos de proveedores. Consulta los [comandos de preparación, versiones de módulos comprobadas y conexión TLS segura](docs/GETTING-STARTED.md). Ningún script instala dependencias automáticamente.

Trabaja desde la carpeta completa recibida. Si es una distribución sin historial y contiene SHA256SUMS, verifícala antes de usarla:

```bash
python3 -B tools/build_offline_candidate.py . --verify
```

Una copia fuente Git no contiene el manifiesto generado de distribución. En una sesión PowerShell aprobada puedes consultar `Get-Help ./scripts/Invoke-VMwareToolkit.ps1 -Full`. El uso en vivo requiere seguir el [procedimiento de sesión autorizada](docs/VCENTER-FIRST-RUN.md); las credenciales permanecen en memoria y TLS sigue validándose.

## Validación y compatibilidad

La [matriz por herramienta](docs/TOOL-VALIDATION-MATRIX.md) distingue análisis estático, simulación offline y observaciones reales limitadas. Combinaciones observadas: vCenter 8.0.3 build 24022515 y ESXi 8.0.3 build 24022510, con PowerCLI Core 13.5.1.25718932 / Vim 9.1.0.25718932. ESXi 9.0.1 build 24957456 tiene **procedencia del medio de terceros sin acreditar** y carece de cobertura positiva de VM/snapshots. Son observaciones, no soporte general VMware ni certificación del fabricante.

**Los analizadores VCF son exclusivamente offline y no se han validado funcionalmente contra un despliegue VCF real.** Las referencias oficiales mutables no acreditan compatibilidad con builds VCF 9.x. SourceVersion es descriptivo; no se adivinan unidades de tiempo, datos ausentes ni contratos no soportados.

El candidato público supera **251 casos Pester y diez pruebas Python**, además de PSScriptAnalyzer con las reglas del proyecto y Gitleaks con redacción. [Métodos de validación y límites de CI](VALIDATION.md). El workflow de GitHub solo usa mocks/fixtures ficticios e instala módulos de prueba con versiones fijadas en un runner desechable; no requiere credenciales VMware. Sus comandos de prueba se ejecutaron localmente; no se ha realizado una ejecución alojada en GitHub.

Con las dependencias de prueba existentes y aprobadas:

```powershell
./tests/Invoke-Validation.ps1
```

```bash
python3 -B -m unittest discover -s tests -p 'test_*.py'
python3 -B tools/check_public_content.py
```

Conserva exportaciones reales, conexiones, credenciales, identificadores y errores originales fuera de Git. Limitar campos no anonimiza los datos. Las pruebas no conectan a VMware. El modificador DNS permanece limitado a WhatIf y fuera del ejecutor central; WhatIf en el ejecutor central suprime la escritura HTML, no las consultas de lectura.

## Contribuir

Consulta [CONTRIBUTING](CONTRIBUTING.md), [seguridad](SECURITY.md), [pruebas comunitarias de laboratorio](docs/COMMUNITY-TESTING.md), [plantilla de resultados](docs/TEST-RESULT-TEMPLATE.md) y [cambios](CHANGELOG.md). Aporta reproducciones ficticias y procedencia con autorización acreditada. Conserva MIT y las atribuciones de terceros obligatorias. No aportes exportaciones/capturas reales ni deduzcas compatibilidad a partir de mocks.
