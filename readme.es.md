# 🍺 BrewStore

> [!IMPORTANT]
> **Aviso de cierre y archivado del proyecto**: BrewStore ha llegado oficialmente al final de su ciclo de vida activo y queda archivado (sunset). El código sigue disponible bajo la Licencia MIT para consulta histórica y forks comunitarios. ¡Muchísimas gracias a todos los que usaron y apoyaron BrewStore!

<div align="center">

**El Gestor de Paquetes Nativo y Compañero de Homebrew Definitivo para macOS**  
*Interfaz gráfica ultrarrápida en SwiftUI nativo y compañero de terminal CLI para casks, formulae, servicios en segundo plano, fijación de versiones y auditorías de seguridad.*

[![Estado: Archivado](https://img.shields.io/badge/Estado-Archivado%20%2F%20Cerrado-red.svg?style=flat-square)](https://github.com/AMFI-Disable/BrewStore)
[![Platform: macOS Sonoma+](https://img.shields.io/badge/Plataforma-macOS%2014%2B%20(Sonoma%20%2F%20Sequoia%20%2F%20Tahoe)-blue.svg?style=flat-square&logo=apple)](https://apple.com)
[![Swift: 5.10+](https://img.shields.io/badge/Swift-5.10%2B-orange.svg?style=flat-square&logo=swift)](https://swift.org)
[![Release: v1.0.0](https://img.shields.io/badge/Versi%C3%B3n-v1.0.0-blue.svg?style=flat-square&logo=github)](https://github.com/AMFI-Disable/BrewStore/releases)
[![Tests: 345 / 345 Passed](https://img.shields.io/badge/Pruebas-339%20%2F%20339%20Superadas%20(100%25)-success.svg?style=flat-square&logo=checkmarx)](#-pruebas-automatizadas-y-control-de-calidad)
[![License: MIT](https://img.shields.io/badge/Licencia-MIT-blue.svg?style=flat-square)](license)
[![Pricing: Free & Open-Source](https://img.shields.io/badge/Precio-100%25%20Gratuito%20y%20C%C3%B3digo%20Abierto-success.svg?style=flat-square)](#-por-qu%C3%A9-brewstore-frente-a-caskhub-y-taphouse-pro-1999)
[![Privacidad: Cero Telemetría](https://img.shields.io/badge/Privacidad-Cero%20Telemetr%C3%ADa%20%2F%20100%25%20Local-purple.svg?style=flat-square)](#privacidad-y-seguridad-primero)

---

## 🌐 Seleccionar Idioma / Select Language / 选择语言 / 言語を選択 / Langue / Sprache

**[English](readme.md)** •
**[简体中文](readme.zh-cn.md)** •
**[繁體中文](readme.zh-tw.md)** •
**[日本語](readme.ja.md)** •
**[Español](readme.es.md)** •
**[Français](readme.fr.md)** •
**[Deutsch](readme.de.md)**

---

### 🧭 Enlaces Rápidos

[🍺 Instalación con Cask](#opcion-1-cask-oficial-de-homebrew-recomendado) •
[✨ Características Principales](#-caracter%C3%ADsticas-principales) •
[⌨️ Atajos de Teclado](#atajos-de-teclado) •
[💻 CLI para Terminal](#-compa%C3%B1ero-cli-brewstore) •
[🛡️ Seguridad y Rollback](#arquitectura-de-seguridad) •
[📊 Tabla Comparativa](#-por-qu%C3%A9-brewstore-frente-a-caskhub-y-taphouse-pro-1999) •
[🧪 Pruebas Automatizadas](#-pruebas-automatizadas-y-control-de-calidad) •
[🗺️ Hoja de Ruta](#hoja-de-ruta)

</div>

---

## 📖 ¿Qué es BrewStore?

**BrewStore** es la aplicación de escritorio definitiva para la gestión de paquetes en macOS. Diseñada con **SwiftUI** y **AppKit** nativos, combina la potencia de la consola de Homebrew con la elegancia y fluidez de una App Store galardonada.

- **Búsquedas instantáneas**: Más de 10.000 paquetes indexados en memoria con respuesta inferior a 20 ms.
- **Desinstalaciones seguras con vista previa**: Comprobación anticipada de dependencias inversas e impacto en el sistema.
- **Instantáneas y Rollback estilo Time Machine**: Copias de seguridad automáticas antes de cambios críticos con reversión en 1 clic.
- **Telemetría de servicios**: Monitorización en tiempo real de CPU, memoria RAM y puertos TCP en servicios en segundo plano.
- **Sincronización Git en la nube**: Respaldo seguro de `~/Brewfile` en GitHub, GitLab, Codeberg, Forgejo o Gitea.

---

## ⚡ Arquitectura y Subsistemas

```text
+-----------------------------------------------------------------------------------------+
|                                  Capa de Interfaz GUI                                   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | Lanzador ⌘K       |  | Carrusel Spotlight |  | Lienzo Dependencias|  | Barra Menú|   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
|   | Fijación Versión  |  | Votación Comunidad |  | Test de Servidores|  | Favoritos |   |
|   +-------------------+  +--------------------+  +-------------------+  +-----------+   |
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                             Motor Central de BrewStore                                  |
|   * FastCacheEngine (Índice <20ms)             * PackagePinningManager (Fijación atómica)|
|   * SnapshotManager (Copias de seguridad)      * UninstallCoordinator (Puerta de examen)|
|   * LockCoordinationManager (Bloqueos PID)     * ServiceTelemetryMonitor (CPU/RAM/Puertos)
|   * MirrorLatencyBenchmarkEngine (CDN)         * GitServiceManager (GitHub/GitLab/FOSS) |
|   * DockLifecycleManager (Ventanas y Dock)     * TapHealthManager (Auditoría e Integración)
+--------------------------------------------+--------------------------------------------+
                                             |
+--------------------------------------------+--------------------------------------------+
|                             Puentes con el Sistema macOS                                |
|   * Motor Homebrew CLI (/opt/homebrew o /usr/local)                                     |
|   * Mac App Store Bridge (mas-cli con recibos y actualizaciones unificadas)             |
|   * Daemon macOS LaunchAgent (com.amfi-disable.brewstore.autoupdate.plist)              |
|   * Seguridad LocalAuthentication (Touch ID y autorización biométrica)                  |
+-----------------------------------------------------------------------------------------+
```

---

## ✨ Características Principales

### 👑 Los 5 Pilares del Gestor Completo de Aplicaciones para Mac

1. **🏬 Gestión Unificada de Doble Tienda y Recomendación de Homebrew**
   - Agrupa casks de Homebrew, formulae de línea de comandos, aplicaciones de Mac App Store (`mas-cli`) y aplicaciones externas no gestionadas en un inventario único y buscable.
   - Detecta automáticamente aplicaciones disponibles en ambas tiendas y recomienda Homebrew por sus actualizaciones más rápidas, compatibilidad con scripts CLI y ausencia de peticiones de contraseña de Apple ID.
   - Detección nativa de recibos de la App Store (`Contents/_MASReceipt/receipt`) con conversión no destructiva a Homebrew en 1 clic.

2. **🧹 Analizador de Almacenamiento por App y Limpiador Seguro de Caché**
   - Desglose detallado del almacenamiento en 3 columnas: **Tamaño del binario**, **Cachés y registros**, y **Datos de la aplicación**.
   - Botón específico **«Limpiar cachés»**: traslada los archivos temporales a la Papelera (`~/.Trash`) con total seguridad, liberando gigabytes mientras mantiene intactas las sesiones de usuario y los ajustes.

3. **🍎 Inspector de Arquitectura Apple Silicon Nativo y Migración Rosetta 2**
   - Distintivos visuales en cada fila de aplicación: `ARM64 Nativo` (verde), `Universal` (azul) y `Rosetta 2` (naranja de advertencia).
   - Banner de alerta que identifica aplicaciones heredadas Intel x86_64 que se ejecutan bajo emulación Rosetta 2, con opción de 1 clic **«Migrar todo a Apple Silicon»** para recuperar ciclos de CPU y prolongar la batería.

4. **⚙️ Elementos de Inicio y Gestión de Daemons LaunchAgent de macOS**
   - Centraliza los servicios de Homebrew, LaunchAgents de usuario (`~/Library/LaunchAgents`), LaunchAgents del sistema (`/Library/LaunchAgents`) y elementos de inicio de sesión de macOS en una vista `ServicesView` unificada.
   - Monitorización en tiempo real de CPU, memoria física residente (RSS) y puertos TCP, con interruptores de activación y eliminación segura en la papelera.

5. **🚀 Configuración Completa de Mac en 1 Comando y Motor de Transferencia Blueprint**
   - Exportación exhaustiva de un **Mac Blueprint** que abarca paquetes de Homebrew, taps, aplicaciones de Mac App Store (`mas "<name>", id: <id>`), versiones fijadas y preferencias.
   - Genera un script Shell idempotente de arranque en un comando e incluye restauración nativa en `MultiMachineSyncView` para clonar su entorno en cuestión de minutos.

### 🛍️ 6. Experiencia de App Store Moderna para Homebrew

- **Historias Editoriales y Spotlight**: Descubra herramientas destacadas para macOS con análisis de versiones y novedades.
- **Community Showdown**: Torneos comunitarios sin servidores basados en GitHub Discussions para votar por las mejores herramientas.
- **Kits para Desarrolladores**: Paquetes de instalación en 1 clic para Full-Stack, Swift/iOS, DevOps, Rust, Ciencia de Datos y Machine Learning.
- **Lista de Deseos**: Guarde sus herramientas preferidas de forma independiente al estado de instalación del sistema.

### 🛡️ 7. Arquitectura de Seguridad y Copias Time Machine <a id="arquitectura-de-seguridad"></a>

- **Fijación Atómica de Versiones**: Bloquee versiones de paquetes críticos directamente desde la vista detallada o el menú contextual, con reversión automática en caso de error.
- **Vista Previa en Desinstalación**: Inspección anticipada de dependencias inversas afectadas y paquetes huérfanos antes de confirmar.
- **Copias de Seguridad y Rollback en 1 Clic**: Registro automático de instantáneas del sistema antes de operaciones de modificación con visualización de diferencias.
- **Coordinación Proactiva de Bloqueos PID**: Evita conflictos con procesos concurrentes de Homebrew.

### 🌐 8. Prueba de Servidores Espejo y Selector de CDN

- **Medición de Latencia en Vivo**: Pruebe la velocidad de descarga con los servidores de Fastly CDN, USTC, TUNA y Aliyun.
- **Selector en 1 Clic**: Aplique los servidores espejo más rápidos en `HOMEBREW_API_DOMAIN` y `HOMEBREW_BOTTLE_DOMAIN`.

### 💻 9. Icono en Barra de Menús y CLI para Terminal

- **Ventana Rígida en la Barra de Menús**: Diseño geométrico estricto sin distorsiones para comprobar actualizaciones y servicios.
- **Herramienta CLI Completa (`brewstore`)**: Ejecute auditorías, alterne versiones de entornos y limpie cachés desde el terminal.

### 🔄 10. Sincronización en la Nube con Múltiples Proveedores Git

- Sincronice sus paquetes y configuración directamente con `~/Brewfile`.
- Soporte para **GitHub Gists**, **GitLab Snippets**, **Codeberg**, **Forgejo** e instancias autohospedadas de **Gitea**.

---

## ⚡ Instalación

### Opción 1: Cask Oficial de Homebrew (Recomendado) <a id="opcion-1-cask-oficial-de-homebrew-recomendado"></a>

```bash
brew tap AMFI-Disable/brewstore
brew install --cask brewstore
```

Para actualizar:

```bash
brew upgrade --cask brewstore
```

---

### Opción 2: Paquete DMG Manual (GitHub Releases)

Descargue el paquete `.dmg` verificado desde [GitHub Releases](https://github.com/AMFI-Disable/BrewStore/releases). Verifique la suma de comprobación SHA-256 tras la descarga:

```bash
shasum -a 256 brewstore-1.0.0.dmg
```

#### Autorización de macOS Gatekeeper (Compilación de Código Abierto no Notarizada)

Dado que BrewStore es un proyecto de código abierto distribuido sin un certificado de pago Apple Developer ID (99 USD/año), macOS Gatekeeper pone en cuarentena los paquetes de aplicaciones descargados en su primer inicio.

Para eliminar el atributo de cuarentena a través de la Terminal:

```bash
sudo xattr -r -c /Applications/BrewStore.app
```

Alternativamente, abra **Ajustes del Sistema > Privacidad y seguridad**, desplácese hasta la sección Seguridad y haga clic en **Abrir de todos modos** (o mantenga pulsada la tecla `Control` mientras hace clic en la aplicación en el Finder y elija **Abrir**).

---

### Opción 3: Compilación desde el Código Fuente

```bash
# Clonar repositorio
git clone https://github.com/AMFI-Disable/BrewStore.git
cd BrewStore

# Generar proyecto con XcodeGen
xcodegen generate

# Compilar en configuración Release
xcodebuild -scheme BrewStore -configuration Release -destination 'platform=macOS' build

# Ejecutar el conjunto de pruebas automatizadas (345 pruebas)
xcodebuild test -scheme BrewStore -destination 'platform=macOS'
```

---

## ⌨️ Atajos de Teclado <a id="atajos-de-teclado"></a>

| Atajo | Función | Descripción |
| :--- | :--- | :--- |
| <kbd>⌘ K</kbd> | **Paleta de Comandos** | Lanzador rápido (`> upgrade all`, `> cleanup`, `> benchmark`) y búsqueda global |
| <kbd>⌘ R</kbd> | **Recargar Catálogo** | Actualizar paquetes locales, servicios y estado de actualizaciones |
| <kbd>⌘ F</kbd> | **Buscar** | Enfocar inmediatamente el campo de búsqueda de la vista actual |
| <kbd>⌘ ,</kbd> | **Preferencias** | Ajustes de la aplicación, servidores espejo y sincronización |
| <kbd>⌘ 1</kbd> | **Descubrir** | Ir a la pantalla de destacados y aplicaciones en tendencia |
| <kbd>⌘ 2</kbd> | **Instalados** | Ver fórmulas y casks instalados en el sistema |
| <kbd>⌘ 3</kbd> | **Actualizaciones** | Revisar paquetes desactualizados y tiempos estimados |
| <kbd>⌘ 4</kbd> | **Servicios** | Monitorizar y gestionar daemons en segundo plano |
| <kbd>⌘ 5</kbd> | **Dependencias** | Abrir el lienzo gráfico bidireccional de dependencias |
| <kbd>⌘ 6</kbd> | **Lista de Deseos** | Ver paquetes guardados para más adelante |
| <kbd>⌘ 7</kbd> | **Kits de Desarrollo** | Paquetes de software listos para usar según el perfil |
| <kbd>⌘ 8</kbd> | **Mantenimiento** | Diagnóstico, limpieza de caché y eliminación de huérfanos |

---

## 💻 Compañero CLI `brewstore`

Disponible en `/opt/homebrew/bin/brewstore` o `/usr/local/bin/brewstore`:

```bash
# Adoptar aplicaciones de /Applications no gestionadas
brewstore adopt [--all]

# Cambiar la versión activa de una herramienta
brewstore switch node 20
brewstore switch python 3.12
brewstore switch postgresql 16

# Ejecutar auditoría de vulnerabilidades CVE (puntuación 0-100)
brewstore audit

# Comprobar y actualizar aplicaciones de la Mac App Store
brewstore mas list
brewstore mas upgrade

# Comprobar la salud del sistema y espacio en disco
brewstore health

# Liberar espacio (limpiar caché y dependencias huérfanas)
brewstore clean

# Abrir la interfaz gráfica nativa
brewstore launch
```

---

## 🌟 ¿Por qué BrewStore frente a CaskHub y Taphouse Pro ($19.99)?

| Vertical | **BrewStore** | **Taphouse Pro** ($19.99) | **CaskHub** |
| :--- | :---: | :---: | :---: |
| **Precio y Licencia** | **100% Gratis y Código Abierto MIT** | $19.99 Comercial / Propietario | Gratuito |
| **Privacidad** | **Cero Telemetría / 100% Local** | Analíticas de terceros | Desconocido |
| **Pruebas Automatizadas** | **339 Métodos XCTest (100% Éxito)** | No publicado | Muy bajo |
| **Limpieza de Caché por App** | **✅ No destructivo hacia la papelera (~/.Trash)** | ❌ No | ❌ No |
| **Apple Silicon vs Rosetta 2** | **✅ Detección auto y migración en 1 clic** | ❌ No | ❌ No |
| **macOS LaunchAgents y Elementos de Inicio** | **✅ Telemetría completa, PID y RAM** | ⚠️ Solo servicios | ❌ No |
| **Motor de Blueprint en 1 Comando** | **✅ Formulae, Casks, MAS y Ajustes** | ❌ No | ❌ No |
| **Inventario Unificado de 2 Tiendas** | **✅ Recomendación preferente de Homebrew** | ❌ No | ❌ No |
| **Vista Previa en Desinstalación** | **✅ Alertas de impacto en cascada** | ❌ No | ❌ No |
| **Instantáneas en 1 Clic** | **✅ Comparación y reversión automática** | ⚠️ Solo lectura | ❌ No |
| **Fijación Atómica de Versiones** | **✅ Reversión ante fallos** | ⚠️ Solo fórmulas | ❌ No |
| **Telemetría de Servicios** | **✅ CPU, RAM y Puertos en directo** | ⚠️ Solo estado | ❌ No |
| **Prueba de Servidores Espejo** | **✅ Fastly, USTC, TUNA, Aliyun** | ❌ No | ❌ No |
| **Sincronización Git en la Nube** | **✅ GitHub, GitLab, Codeberg, Gitea** | ❌ Solo GitHub | ❌ No |
| **Lienzo de Dependencias** | **✅ Gráfico interactivo bidireccional** | ⚠️ Árbol estático | ❌ No |
| **Icono en la Barra de Menús** | **✅ Ventana rígida sin distorsiones** | ⚠️ Básico | ❌ No |
| **Herramienta CLI para Terminal** | **✅ Incluida (`brewstore`)** | ❌ No | ❌ No |
| **Velocidad de Inicio** | **⚡ &lt;20ms (Índice en memoria)** | 🐢 2–3 s | 🐢 2–3 s |

---

## 🧪 Pruebas Automatizadas y Control de Calidad

BrewStore mantiene un conjunto exhaustivo de pruebas automatizadas que abarcan toda la lógica de negocio, coordinadores, límites de seguridad e interacciones de usuario.

```bash
# Ejecución del conjunto de pruebas mediante Xcodebuild
xcodegen generate
xcodebuild test -scheme BrewStore -destination "platform=macOS"
```

### Suites de Pruebas Verificadas (345 / 345 Superadas)

- `AppStorageInspectorTests`: Limpieza de caché por aplicación no destructiva, desglose de tamaño (binario vs cachés vs datos) y protección de la papelera.
- `AppleSiliconMigrationTests`: Detección de emulación bajo Rosetta 2, identificación de candidatos nativos ARM64 y mapeo arquitectónico.
- `BackgroundItemsManagerTests`: Análisis de plists de LaunchAgents de usuario y sistema, comandos launchctl e ítems de inicio de sesión.
- `MacBlueprintEngineTests`: Análisis de sintaxis MAS para Brewfile, generación de script de arranque y restauración de Blueprint.
- `UnifiedAppManagerTests`: Fusión de inventario de doble tienda, preferencia de recomendación de Homebrew y actualización global en 1 clic.
- `SidebarDestinationSelectionTests`: Aislamiento riguroso de destinos de navegación y encabezados de grupos accesibles.
- `MenuBarDistortionPreventionTests`: Geometría rígida del popover y supresión de distorsiones visuales.
- `PackagePinningSynchronizationTests`: Consistencia atómica del gestor de fijación, estado de Homebrew y reversión ante fallos.
- `SpotlightCarouselTargetingTests`: Prevención de condiciones de carrera en el carrusel y vinculación con la lista de deseos.
- `UninstallCoordinatorTests`: Puerta de examen seguro y cálculo de dependencias inversas.
- `TapHealthManagerTests`: Auditorías de salud para taps oficiales y de terceros y seguimiento de CI.
- `SpeedTestManagerTests`: Análisis de tiempos de respuesta de servidores espejo y estimación de duración de actualizaciones.
- `TCCPermissionManagerTests`: Detección de permisos de accesibilidad y extensiones del sistema.
- `BrewStoreLockManagerTests`: Seguimiento de bloqueos PID, gestión de tiempos de espera y liberación de bloqueos huérfanos.
- `CellarScannerTests`: Detección multiversión en Cellar y conmutación de enlaces simbólicos.
- `MASReceiptScannerTests`: Análisis de recibos de paquetes de Mac App Store y resolución de versiones.
- `ExecutionSecurityBoundaryTests`: Saneamiento de shell, validación de rutas y prevención de inyecciones de argumentos.

---

## 🛡️ Privacidad y Seguridad Primero <a id="privacidad-y-seguridad-primero"></a>

- **Cero Telemetría**: Sin seguimiento, herramientas de análisis de terceros ni envío de métricas.
- **Ejecución Local**: Todas las operaciones se realizan exclusivamente mediante la instalación local de Homebrew.
- **Autorización Biométrica**: Acciones críticas protegidas mediante Touch ID y Apple Watch con `LocalAuthentication`.

---

## 🗺️ Hoja de Ruta <a id="hoja-de-ruta"></a>

- [x] **v1.0.0**: Rediseño nativo en SwiftUI, motor FastCache, paleta ⌘K y lienzo interactivo de dependencias.
- [x] **v1.0.5**: Sincronización Git multi-proveedor y torneos comunitarios.
- [x] **v1.1.0**:
  - [x] Vista previa antes de desinstalar con advertencias de dependencias inversas.
  - [x] Gestor de fijación atómica de versiones con reversión segura.
  - [x] Estabilización geométrica del icono en la barra de menús.
  - [x] 345 pruebas de regresión superadas con 0 fallos.
- [ ] **v1.2.0**:
  - [ ] Caché P2P en red local para entornos con múltiples Mac.
  - [ ] Ejecuciones de prueba en entornos aislados con Apple Virtualization Framework.
  - [ ] Asistente de creación de taps personalizados para desarrolladores independientes.

---

## 📄 Licencia

BrewStore se distribuye bajo la [Licencia MIT](license). Código abierto, libre e independiente.
