#!/usr/bin/env python3
"""Generate the checked-in Xcode project with only Python's standard library."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
objects = {}

def ident(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(name, text):
    objects[ident(name)] = text
    return ident(name)

def quote(text):
    return json.dumps(str(text))

def refs(items):
    return '(' + ', '.join(items) + (',' if items else '') + ')'

app_files = []
app_build = []
for file in sorted((root / 'Sources/AIBuddy').glob('*.swift')):
    ref = add(str(file.relative_to(root)), f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(file.relative_to(root))}; sourceTree = SOURCE_ROOT;')
    app_files.append(ref)
    app_build.append(add('build-' + file.name, f'isa = PBXBuildFile; fileRef = {ref};'))
resources = add('resources', 'isa = PBXFileReference; lastKnownFileType = folder; path = Sources/AIBuddy/Resources; sourceTree = SOURCE_ROOT;')
resource_build = add('resources-build', f'isa = PBXBuildFile; fileRef = {resources};')
ui_ref = add('uitest-file', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AIBuddyUITests/WorkspaceUITests.swift; sourceTree = SOURCE_ROOT;')
ui_build = add('uitest-build', f'isa = PBXBuildFile; fileRef = {ui_ref};')
base = add('base-config', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Config/Base.xcconfig; sourceTree = SOURCE_ROOT;')
app_product = add('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = AIBuddy.app; sourceTree = BUILT_PRODUCTS_DIR;')
ui_product = add('ui-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = AIBuddyUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products', f'isa = PBXGroup; children = {refs([app_product, ui_product])}; name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = {refs(app_files + [resources, ui_ref, base, products])}; sourceTree = "<group>";')
package = add('package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
core = add('core-product', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = BuddyCore;')
core_build = add('core-build', f'isa = PBXBuildFile; productRef = {core};')

def phase(name, kind, files):
    return add(name, f'isa = {kind}; buildActionMask = 2147483647; files = {refs(files)}; runOnlyForDeploymentPostprocessing = 0;')

app_phases = [phase('app-sources', 'PBXSourcesBuildPhase', app_build), phase('app-frameworks', 'PBXFrameworksBuildPhase', [core_build]), phase('app-resources', 'PBXResourcesBuildPhase', [resource_build])]
ui_phases = [phase('ui-sources', 'PBXSourcesBuildPhase', [ui_build]), phase('ui-frameworks', 'PBXFrameworksBuildPhase', []), phase('ui-resources', 'PBXResourcesBuildPhase', [])]

def configs(name, settings):
    ids = []
    for config in ['Debug', 'Release']:
        current = dict(settings)
        current['SWIFT_OPTIMIZATION_LEVEL'] = '-Onone' if config == 'Debug' else '-O'
        if config == 'Debug':
            current['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DEBUG'
            current['ENABLE_TESTABILITY'] = 'YES'
        text = ' '.join(f'{key} = {quote(value)};' for key, value in current.items())
        ids.append(add(name + '-' + config, f'isa = XCBuildConfiguration; baseConfigurationReference = {base}; buildSettings = {{ {text} }}; name = {config};'))
    return add(name + '-configs', f'isa = XCConfigurationList; buildConfigurations = {refs(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

project_configs = configs('project', {'SDKROOT': 'macosx', 'CLANG_ENABLE_MODULES': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'complete'})
app_configs = configs('app', {'PRODUCT_NAME': 'AIBuddy', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.aibuddy.desktop', 'INFOPLIST_FILE': 'Config/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/../Frameworks', 'COMBINE_HIDPI_IMAGES': 'YES'})
ui_configs = configs('ui', {'PRODUCT_NAME': 'AIBuddyUITests', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.aibuddy.desktop.uitests', 'GENERATE_INFOPLIST_FILE': 'YES', 'TEST_TARGET_NAME': 'AIBuddy'})
proxy = add('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("app-target")}; remoteInfo = AIBuddy;')
dependency = add('ui-dependency', f'isa = PBXTargetDependency; target = {ident("app-target")}; targetProxy = {proxy};')
app = add('app-target', f'isa = PBXNativeTarget; buildConfigurationList = {app_configs}; buildPhases = {refs(app_phases)}; buildRules = (); dependencies = (); name = AIBuddy; packageProductDependencies = {refs([core])}; productName = AIBuddy; productReference = {app_product}; productType = "com.apple.product-type.application";')
ui = add('ui-target', f'isa = PBXNativeTarget; buildConfigurationList = {ui_configs}; buildPhases = {refs(ui_phases)}; buildRules = (); dependencies = {refs([dependency])}; name = AIBuddyUITests; productName = AIBuddyUITests; productReference = {ui_product}; productType = "com.apple.product-type.bundle.ui-testing";')
project = add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {ui} = {{ TestTargetID = {app}; }}; }}; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; packageReferences = {refs([package])}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([app, ui])};')
content = '// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'
content += ''.join(f'  {key} = {{ {value} }};\n' for key, value in sorted(objects.items()))
content += f' }};\n rootObject = {project};\n}}\n'
(root / 'AIBuddy.xcodeproj/project.pbxproj').write_text(content)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="AIBuddy.app" BlueprintName="AIBuddy" ReferencedContainer="container:AIBuddy.xcodeproj"/>
    </BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
    <Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ui}" BuildableName="AIBuddyUITests.xctest" BlueprintName="AIBuddyUITests" ReferencedContainer="container:AIBuddy.xcodeproj"/></TestableReference></Testables>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app}" BuildableName="AIBuddy.app" BlueprintName="AIBuddy" ReferencedContainer="container:AIBuddy.xcodeproj"/></BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(root / 'AIBuddy.xcodeproj/xcshareddata/xcschemes/AIBuddy.xcscheme').write_text(scheme)
