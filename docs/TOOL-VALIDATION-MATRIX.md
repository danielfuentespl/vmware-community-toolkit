# Matriz de validación por herramienta

Observaciones revisadas a 18 de octubre de 2026. Son **25 herramientas más un auxiliar de laboratorio**. Esta es la matriz de observaciones revisadas, no una certificación general ni una promesa para otras versiones.

Tuplas observadas: PowerShell 7.6.7/Linux x64, Core 13.5.1.25718932, Vim 9.1.0.25718932; vCenter 8.0.3/24022515, ESXi8 8.0.3/24022510 y ESXi9 9.0.1/24957456. ESXi8 gestionado y directo es el mismo host. Omarchy, otras versiones, escala, HCL y soporte del fabricante no quedan certificados.

**VALIDADO** indica la función y objetos positivos observados, no cobertura total ni salud/cumplimiento. **PARCIAL** indica límites materiales; **BLOQUEADO** señala un requisito/contrato excluido; **NO PROBADO** significa sin prueba funcional de ese origen. N.A. indica que una API vSphere no es la fuente del analizador. “Datos” describe procesamiento offline de capturas reales, no una conexión del script.

ESXi9 tiene metadatos de tercero/community en el medio original y en el perfil instalado. Por ello su columna permanece PARCIAL incluso para lectores que produjeron observaciones no vacías: no se acredita una imagen oficial. Se conserva el PASS de esos casos observados en la evidencia histórica; no se eleva a compatibilidad de producto oficial ni se altera retroactivamente el resultado bruto.

| Herramienta | vCenter 8 | ESXi8 directo | ESXi9 directo | Verificación local | Cobertura / límite |
|---|---|---|---|---|---|
| [Get-VMInventory.ps1](../scripts/Reporting/Get-VMInventory.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | VM/CPU/RAM/estado; ESXi9 solo rama vacía. |
| [Get-VMwareToolsStatus.ps1](../scripts/Reporting/Get-VMwareToolsStatus.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Tools de VM reales ESXi8, incluida Ubuntu; ESXi9 sin VM. |
| [Get-SnapshotReport.ps1](../scripts/Reporting/Get-SnapshotReport.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Dos snapshots ESXi8: árbol/fecha API y tamaño nativo; sin prueba positiva ESXi9. |
| [Get-OldSnapshots.ps1](../scripts/Reporting/Get-OldSnapshots.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Edad real con umbral 0,00001 días y exclusión a 7 días; ningún objeto realmente antiguo. |
| [Get-DatastoreCapacity.ps1](../scripts/Storage/Get-DatastoreCapacity.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Un datastore por host; no escala, vSAN físico ni inaccesibilidad real. |
| [Get-VMHostHealth.ps1](../scripts/Health/Get-VMHostHealth.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Resumen observado; gray directo no es veredicto de fallo ni certificación hardware. |
| [Get-VMHostDnsReport.ps1](../scripts/Reporting/Get-VMHostDnsReport.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Configuración observada; no saneamiento DNS ni prueba integral de resolución. |
| [Get-VMHostNtpConfiguration.ps1](../scripts/Network/Get-VMHostNtpConfiguration.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Lista configurada; no medición de deriva por este lector. |
| [Get-VMHostSecurityConfiguration.ps1](../scripts/Security/Get-VMHostSecurityConfiguration.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Lockdown y servicios; no evaluación normativa ni explotación. |
| [Get-VMHostFirewallReport.ps1](../scripts/Network/Get-VMHostFirewallReport.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Excepciones observadas; campos opcionales Unknown; no política efectiva completa. |
| [Get-VMHostSyslogConfiguration.ps1](../scripts/Logging/Get-VMHostSyslogConfiguration.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Cinco claves; entrega de logs no comprobada. |
| [Get-VMHostTimeConfiguration.ps1](../scripts/Network/Get-VMHostTimeConfiguration.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Protocolo/estado reportado; no modificación ni medición autónoma del reloj. |
| [Get-VMHostAdvancedSettings.ps1](../scripts/Security/Get-VMHostAdvancedSettings.ps1) | VALIDADO | VALIDADO | PARCIAL | Estático + Pester | Solo cinco claves syslog revisadas; no volcado genérico. |
| [Get-VMCertificateExpiry.ps1](../scripts/Security/Get-VMCertificateExpiry.ps1) | VALIDADO | BLOQUEADO | BLOQUEADO | Estático + Pester | Scope VMHost gestionado y VCenter; contrato excluye ESXi directo deliberadamente. |
| [Set-VMHostDnsServers.ps1](../scripts/Network/Set-VMHostDnsServers.ps1) | NO PROBADO | NO PROBADO | NO PROBADO | Pester/WhatIf simulado | No ejecución real, tampoco WhatIf real; escritura excluida. |
| [Invoke-VMwareToolkit.ps1](../scripts/Invoke-VMwareToolkit.ps1) | PARCIAL | PARCIAL | PARCIAL | Estático + Pester | Inventory/Operations PASS VC8/ESXi8 con umbral corto; Security/All Incomplete; ESXi9 vacío/procedencia. |
| [New-vSphereHealthReport.ps1](../scripts/Reporting/New-vSphereHealthReport.ps1) | VALIDADO (datos) | VALIDADO (datos) | PARCIAL (datos) | Renderer local real + Pester | HTML offline con entradas reales; no transporte propio ni autenticación. Límites de fuente conservados. |
| [Compare-vSphereInventory.ps1](../scripts/Reporting/Compare-vSphereInventory.ps1) | PARCIAL (datos) | NO PROBADO | NO PROBADO | Pester + comparación real | Datos VC8: Added, PowerState, CPU/RAM y reversión; Removed real pendiente. No conexión propia. |
| [Get-VCFCertificates.ps1](../scripts/VCF/Get-VCFCertificates.ps1) | NO PROBADO / N.A. | NO PROBADO / N.A. | NO PROBADO / N.A. | Pester + JSON ficticio | Analizador offline de exportaciones VCF; sin autenticación ni versión VCF funcional acreditada. |
| [Get-VCFHealth.ps1](../scripts/VCF/Get-VCFHealth.ps1) | NO PROBADO / N.A. | NO PROBADO / N.A. | NO PROBADO / N.A. | Pester + JSON ficticio | Analizador offline de exportaciones VCF; sin autenticación ni versión VCF funcional acreditada. |
| [Get-VCFInventory.ps1](../scripts/VCF/Get-VCFInventory.ps1) | NO PROBADO / N.A. | NO PROBADO / N.A. | NO PROBADO / N.A. | Pester + JSON ficticio | Analizador offline de exportaciones VCF; sin autenticación ni versión VCF funcional acreditada. |
| [Get-VCFLicensingReport.ps1](../scripts/VCF/Get-VCFLicensingReport.ps1) | NO PROBADO / N.A. | NO PROBADO / N.A. | NO PROBADO / N.A. | Pester + JSON ficticio | Analizador offline de exportaciones VCF; sin autenticación ni versión VCF funcional acreditada. |
| [Get-VCFLifecycleStatus.ps1](../scripts/VCF/Get-VCFLifecycleStatus.ps1) | NO PROBADO / N.A. | NO PROBADO / N.A. | NO PROBADO / N.A. | Pester + JSON ficticio | Analizador offline de exportaciones VCF; sin autenticación ni versión VCF funcional acreditada. |
| [Get-VCFOperationsAlerts.ps1](../scripts/VCF/Get-VCFOperationsAlerts.ps1) | NO PROBADO / N.A. | NO PROBADO / N.A. | NO PROBADO / N.A. | Pester + JSON ficticio | Analizador offline de exportaciones VCF; sin autenticación ni versión VCF funcional acreditada. |
| [Get-VCFVersions.ps1](../scripts/VCF/Get-VCFVersions.ps1) | NO PROBADO / N.A. | NO PROBADO / N.A. | NO PROBADO / N.A. | Pester + JSON ficticio | Analizador offline de exportaciones VCF; sin autenticación ni versión VCF funcional acreditada. |
| [Invoke-ToolkitLabValidation.ps1](../scripts/Lab/Invoke-ToolkitLabValidation.ps1) | NO PROBADO | NO PROBADO | NO PROBADO | Preflight/mocks locales | Auxiliar; no se utilizó en las pruebas reales anteriores. |

## Evidencia y alcance

55 casos funcionales acumulados: **41 PASS / 12 PARTIAL / 2 BLOCKED / 0 FAIL finales**. Son casos de validación por origen/función, no 55 herramientas ni 55 tests Pester. No se ha vuelto a conectar a VMware para preparar esta distribución.

Trece lectores ESXi8 directos produjeron datos con permisos ReadOnly acotados y se observó un NoPermission real. No se acredita un rol irreducible ni los permisos mínimos SSO de vCenter; los certificados se consultaron con cuenta administrativa. Dos snapshots reales permitieron comprobar fechas/tamaño y un umbral corto de antigüedad; no existe evidencia de un snapshot realmente mayor de siete días. La comparación verificó alta, estado, CPU/RAM y restauración, pero no retirada real. Se conservaron los límites de perfiles incompletos y campos Unknown.

La procedencia del medio ESXi9 sigue sin acreditar; su columna permanece PARCIAL incluso donde hubo datos. No se presenta como imagen oficial validada. Certificados directos son un límite intencionado. Unknown, NotRun y resultados vacíos no acreditan salud, cumplimiento o visibilidad. Los originales de las evidencias se guardan privadamente y no se distribuyen.
