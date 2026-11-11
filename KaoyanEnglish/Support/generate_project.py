"""Generate the checked-in Xcode project with Python's standard library only."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parents[1]
def uid(s): return hashlib.sha1(s.encode()).hexdigest()[:24].upper()
def q(s): return '"' + s.replace('"', '\\"') + '"'
objects = []
def obj(name, value):
    objects.append(f'{uid(name)} = {{ {value} }};')
    return uid(name)
def refs(xs): return '(' + ','.join(xs) + ',)'
app_sources = sorted((root/'KaoyanEnglish').rglob('*.swift'))
tests = sorted((root/'KaoyanEnglishTests').glob('*.swift'))
resources = sorted((root/'KaoyanEnglish/Resources').glob('*.json'))
file_refs=[]
for p in app_sources + tests + resources:
    rel = str(p.relative_to(root))
    ref = obj(rel, f'isa = PBXFileReference; lastKnownFileType = {"sourcecode.swift" if p.suffix == ".swift" else "text.json"}; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    file_refs.append(ref)
    obj('build:'+rel, f'isa = PBXBuildFile; fileRef = {ref};')
app_prod=obj('app-product','isa = PBXFileReference; explicitFileType = wrapper.application; path = KaoyanEnglish.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_prod=obj('test-product','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = KaoyanEnglishTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products=obj('products',f'isa = PBXGroup; children = {refs([app_prod,test_prod])}; name = Products; sourceTree = "<group>";')
group=obj('root',f'isa = PBXGroup; children = {refs(file_refs+[products])}; sourceTree = "<group>";')
for name, files in [('app-sources',app_sources),('test-sources',tests),('resources',resources)]:
    obj(name, f'isa = {"PBXResourcesBuildPhase" if name == "resources" else "PBXSourcesBuildPhase"}; buildActionMask = 2147483647; files = {refs([uid("build:"+str(p.relative_to(root))) for p in files]) if files else "()"}; runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("app")}; remoteInfo = KaoyanEnglish;')
obj('dependency',f'isa = PBXTargetDependency; target = {uid("app")}; targetProxy = {uid("proxy")};')
common = 'CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; TARGETED_DEVICE_FAMILY = "1,2"; CODE_SIGN_STYLE = Automatic;'
for scope in ['project','app','test']:
    cfgs=[]
    for mode in ['Debug','Release']:
        settings=common
        if mode=='Debug': settings+=' SWIFT_OPTIMIZATION_LEVEL = "-Onone"; ENABLE_TESTABILITY = YES; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;'
        else: settings+=' SWIFT_OPTIMIZATION_LEVEL = "-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";'
        if scope=='app':
            settings+=' PRODUCT_NAME = KaoyanEnglish; PRODUCT_BUNDLE_IDENTIFIER = com.local.kaoyanenglish; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = KaoyanEnglish/App/Info.plist; OTHER_LDFLAGS = "-lsqlite3";'
        if scope=='test':
            settings+=' PRODUCT_NAME = KaoyanEnglishTests; PRODUCT_BUNDLE_IDENTIFIER = com.local.kaoyanenglish.tests; GENERATE_INFOPLIST_FILE = YES; TEST_HOST = "$(BUILT_PRODUCTS_DIR)/KaoyanEnglish.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/KaoyanEnglish"; BUNDLE_LOADER = "$(TEST_HOST)";'
        cfgs.append(obj(scope+mode,f'isa = XCBuildConfiguration; buildSettings = {{ {settings} }}; name = {mode};'))
    obj(scope+'configs',f'isa = XCConfigurationList; buildConfigurations = {refs(cfgs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('app',f'isa = PBXNativeTarget; buildConfigurationList = {uid("appconfigs")}; buildPhases = {refs([uid("app-sources"),uid("frameworks"),uid("resources")])}; buildRules = (); dependencies = (); name = KaoyanEnglish; productName = KaoyanEnglish; productReference = {app_prod}; productType = "com.apple.product-type.application";')
obj('test',f'isa = PBXNativeTarget; buildConfigurationList = {uid("testconfigs")}; buildPhases = {refs([uid("test-sources")])}; buildRules = (); dependencies = {refs([uid("dependency")])}; name = KaoyanEnglishTests; productName = KaoyanEnglishTests; productReference = {test_prod}; productType = "com.apple.product-type.bundle.unit-test";')
obj('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2600; }}; buildConfigurationList = {uid("projectconfigs")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans",en,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([uid("app"),uid("test")])};')
(root/'KaoyanEnglish.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {uid("project")}; }}\n')
def entry(target, product): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target)}" BuildableName="{product}" BlueprintName="{ "KaoyanEnglish" if target=="app" else "KaoyanEnglishTests"}" ReferencedContainer="container:KaoyanEnglish.xcodeproj"/>'
(root/'KaoyanEnglish.xcodeproj/xcshareddata/xcschemes/KaoyanEnglish.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{entry('app','KaoyanEnglish.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{entry('test','KaoyanEnglishTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry('app','KaoyanEnglish.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES"><BuildableProductRunnable runnableDebuggingMode="0">{entry('app','KaoyanEnglish.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
