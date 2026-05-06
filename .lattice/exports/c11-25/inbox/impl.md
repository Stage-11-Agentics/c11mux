 ▐▛███▜▌   Claude Code v2.1.128
▝▜█████▛▘  Opus 4.7 · Claude Max
  ▘▘ ▝▝    ~/Projects/Stage11/code/c11-worktrees/c11-25-surface-lifecycle

❯ Read .lattice/prompts/c11-25-impl.md and follow the instructions.             

  Read 1 file (ctrl+o to expand)

⏺ Bash(echo "CMUX_SURFACE_ID=$CMUX_SURFACE_ID C11_SURFACE_ID=$C11_SURFACE_ID
      CMUX_SHELL_INTEGRATION=$CMUX_SHELL_INTEGRATION
      C11_SHELL_INTEGRATION=$C11_SHELL_INTEGRATIO…)
  ⎿  CMUX_SURFACE_ID=6AEB53B0-D165-43A8-A683-BEC48FB73782 C11_SURFACE_ID= C
     MUX_SHELL_INTEGRATION=1 C11_SHELL_INTEGRATION=

⏺ I'm the Impl sub-agent for C11-25. Let me orient first by setting up c11
  metadata and reading the required documents.

⏺ Bash(c11 identify)
  ⎿  {
       "focused" : {
         "surface_ref" : "surface:38",
     … +19 lines (ctrl+o to expand)

⏺ Bash(c11 set-agent --surface 6AEB53B0-D165-43A8-A683-BEC48FB73782 --type
      claude-code --model claude-opus-4-7 && c11 rename-tab --surface
      6AEB53B0-D165-43A8-A683-BEC4…)
  ⎿  OK surface:41
       model: applied
       terminal_type: applied
     … +7 lines (ctrl+o to expand)

  Read 1 file (ctrl+o to expand)

⏺ Plan is clear. Now I'll set the description and read the remaining required
  docs in parallel.

⏺ Bash(c11 set-description --surface 6AEB53B0-D165-43A8-A683-BEC48FB73782
      "C11-25 — Surface lifecycle perf: webview suspension, off-screen terminal
      throttling, per-sur…)
  ⎿  OK description applied=true source=explicit

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice show C11-25 --full
      2>&1 | head -200)
  ⎿  C11-25 (task_01KQTQ05R0G4CSMJRQPK7XVKY3)  "Surface lifecycle perf: web
     view suspension, off-screen terminal throttling, per-surface frame bud
     get"
     … +186 lines (ctrl+o to expand)
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

⏺ Bash(git status && git log --oneline -10)
  ⎿  On branch c11-25-surface-lifecycle
     Your branch is behind 'origin/main' by 2 commits, and can be fast-forw
     arded.
     … +20 lines (ctrl+o to expand)

⏺ Branch is 2 behind main and can fast-forward. Let me pull, load task tracking,
   and read the c11 skill.

⏺ Bash(git pull --ff-only origin main 2>&1 | tail -5 && git log --oneline -5)
  ⎿     .lattice/events/task_01KQTQ05R0G4CSMJRQPK7XVKY3.jsonl
        .lattice/tasks/task_01KQTQ05R0G4CSMJRQPK7XVKY3.json
     Please move or remove them before you merge.
     … +11 lines (ctrl+o to expand)

  Read 1 file (ctrl+o to expand)

⏺ Pull failed due to untracked .lattice/ files conflicting with main. Let me
  investigate before making moves.

⏺ Bash(cat .gitignore 2>/dev/null | grep -i lattice; echo "---"; git diff --stat
       HEAD..origin/main -- .lattice/ 2>&1 | head -20; echo "---"; git ls-tree
      -r origin/main…)
  ⎿  ---
      .../meta/art_01KQR5RPHTX7F9BNGBMNVP901T.json       |  19 ++
      .../meta/art_01KQR5RSP8PM35RWJ11Z61QGPM.json       |  19 ++
     … +47 lines (ctrl+o to expand)

⏺ Let me check whether the local untracked lattice files match main's tracked
  versions.

⏺ Bash(echo "=== local file ==="; ls -la
      .lattice/tasks/task_01KQTQ05R0G4CSMJRQPK7XVKY3.json 2>&1; echo ""; echo
      "=== main has it ==="; git show origin/main:.lattice/t…)
  ⎿  === local file ===
     -rw-------@ 1 atin  staff  4548 May  4 21:01 .lattice/tasks/task_01KQT
     Q05R0G4CSMJRQPK7XVKY3.json
     … +80 lines (ctrl+o to expand)

⏺ Local copies are outdated; main has newer event/task state. Let me discard
  them and pull cleanly.

⏺ Bash(echo "=== ids.json diff ==="; git diff .lattice/ids.json | head -30; echo
       ""; echo "=== prompts dir ==="; ls -la .lattice/prompts/ 2>&1; echo "";
      echo "=== prom…)
  ⎿  === ids.json diff ===
     diff --git a/.lattice/ids.json b/.lattice/ids.json
     index 7aefff51..5772e281 100644
     … +22 lines (ctrl+o to expand)
⏺ Let me set up task tracking for the 9 commits and resolve the pull conflict.

⏺ Bash(rm -rf .lattice/events/task_01KQTQ05R0G4CSMJRQPK7XVKY3.jsonl
      .lattice/tasks/task_01KQTQ05R0G4CSMJRQPK7XVKY3.json && git checkout --
      .lattice/ids.json && git pul…)
  ⎿   create mode 100644 notes/archive/cmux-37/trident-review-CMUX-37-pack-
     20260504-1543/evolutionary-codex.md
      create mode 100644 notes/archive/cmux-37/trident-review-CMUX-37-pack-
     … +17 lines (ctrl+o to expand)

⏺ Fast-forwarded. Now let me complete task 1 and explore the codebase before
  commit 1.

  Listed 2 directories (ctrl+o to expand)

⏺ Large codebase. Let me dispatch an Explore agent to gather key code sections
  in parallel while I start reading SurfaceMetadataStore directly.

⏺ Explore(Map relevant lifecycle code sections)
  ⎿  Done (36 tool uses · 97.6k tokens · 2m 46s)
  (ctrl+o to expand)

  Read 1 file (ctrl+o to expand)
⏺ Now I have a clear picture. Let me start commit 1: create
  SurfaceLifecycle.swift and register the canonical key.

⏺ Write(Sources/SurfaceLifecycle.swift)
  ⎿  Wrote 146 lines to Sources/SurfaceLifecycle.swift
       2 import Foundation
       3 /// Per-surface lifecycle state.
       4 ///
         underne of four discrete states, mirrored to canonical metadata 
       6 /// `lifecycle_state` so that the sidebar, `c11 tree --json`, th
         e socket,
         ng tond `c11 snapshot` / `restore` can observe it without coupli
       8 /// runtime Swift state.
       9 ///
      10 /// State semantics (per the C11-25 plan):
     … +170 lines (ctrl+o to expand)

⏺ Now register the canonical metadata key.

⏺ Update(Sources/SurfaceMetadataStore.swift)
  ⎿  Added 2 lines, removed 1 line
      17      public static let terminalType = "terminal_type"
      18      public static let title = "title"
      19      public static let description = "description"
      20 +    public static let lifecycleState = "lifecycle_state"       
      21  
      22      /// Non-canonical display hint used by M3's sidebar chip.
      23      public static let modelLabel = "model_label"
      24  
      25      public static let canonical: Set<String> = [
      25 -        role, status, task, model, progress, terminalType, titl
         -e, description                                                 
      26 +        role, status, task, model, progress, terminalType, titl
         +e, description, lifecycleState                                 
      27      ]
      28  
      29      public static let canonicalTerminalTypes: Set<String> = [

⏺ Update(Sources/SurfaceMetadataStore.swift)
  ⎿  Added 1 line
      155          "terminal_type",
      156          "title",
      157          "description",
      158 +        "lifecycle_state",                                    
      159          "claude.session_id",
      160          "claude.session_project_dir"
      161      ]

⏺ Update(Sources/SurfaceMetadataStore.swift)
  ⎿  Added 22 lines
      185              return validateString(key: key, value: value, maxL
           en: 256)
      186          case "description":
      187              return validateString(key: key, value: value, maxL
           en: 2048)
      188 +        case "lifecycle_state":                               
      189 +            // Canonical per-surface lifecycle state (C11-25).
          + The set of                                                   
      190 +            // legal values is defined by `SurfaceLifecycleSta
          +te`; reject                                                   
      191 +            // anything outside that vocabulary so a stale sna
          +pshot or a                                                    
      192 +            // typo can't leak into the runtime path. Length c
          +ap matches                                                    
      193 +            // `SurfaceLifecycleState.metadataMaxLength`.     
      194 +            guard let s = value as? String else {             
      195 +                return .reservedKeyInvalidType(key, "expected 
          +string")                                                      
      196 +            }                                                 
      197 +            if s.count > SurfaceLifecycleState.metadataMaxLeng
          +th {                                                          
      198 +                return .reservedKeyInvalidType(               
      199 +                    key,                                      
      200 +                    "exceeds max length \(SurfaceLifecycleStat
          +e.metadataMaxLength)"                                         
      201 +                )                                             
      202 +            }                                                 
      203 +            if SurfaceLifecycleState(rawValue: s) == nil {    
      204 +                return .reservedKeyInvalidType(               
      205 +                    key,                                      
      206 +                    "must be one of: active, throttled, suspen
          +ded, hibernated"                                              
      207 +                )                                             
      208 +            }                                                 
      209 +            return nil                                        
      210          case "claude.session_id":
      211              // Claude SessionStart's `session_id` is a UUIDv4;
            reject
      212              // anything else. The value is interpolated verbat
           im into

⏺ Need to add SurfaceLifecycle.swift to the Xcode project. Let me check the
  project file structure.

  Searched for 4 patterns, read 1 file, listed 1 directory (ctrl+o to expand)

⏺ IDs are free. Let me add SurfaceLifecycle.swift to the project file at all
  four locations.

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      26      D70A4BF0A1B2C3D4E5F60718 /* WorkspaceMetadataValidatorTests
          .swift in Sources */ = {isa = PBXBuildFile; fileRef = D70A4BF1A
          1B2C3D4E5F60718 /* WorkspaceMetadataValidatorTests.swift */; };
      27      D7005BF0A1B2C3D4E5F60718 /* PersistedMetadata.swift in Sour
          ces */ = {isa = PBXBuildFile; fileRef = D7005BF1A1B2C3D4E5F6071
          8 /* PersistedMetadata.swift */; };
      28      D7010BF0A1B2C3D4E5F60718 /* PaneMetadataStore.swift in Sour
          ces */ = {isa = PBXBuildFile; fileRef = D7010BF1A1B2C3D4E5F6071
          8 /* PaneMetadataStore.swift */; };
      29 +    D7C11250A1B2C3D4E5F60718 /* SurfaceLifecycle.swift in Sourc
         +es */ = {isa = PBXBuildFile; fileRef = D7C11251A1B2C3D4E5F60718
         + /* SurfaceLifecycle.swift */; };                              
      30      D8001BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift in Sou
          rces */ = {isa = PBXBuildFile; fileRef = D8001BF1A1B2C3D4E5F607
          18 /* WorkspaceApplyPlan.swift */; };
      31      D8002BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests.
          swift in Sources */ = {isa = PBXBuildFile; fileRef = D8002BF1A1
          B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests.swift */; };
      32      D8003BF0A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.swift i
          n Sources */ = {isa = PBXBuildFile; fileRef = D8003BF1A1B2C3D4E
          5F60718 /* WorkspaceLayoutExecutor.swift */; };

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      334      D70A4BF1A1B2C3D4E5F60718 /* WorkspaceMetadataValidatorTest
           s.swift */ = {isa = PBXFileReference; lastKnownFileType = sour
           cecode.swift; path = WorkspaceMetadataValidatorTests.swift; so
           urceTree = "<group>"; };
      335      D7005BF1A1B2C3D4E5F60718 /* PersistedMetadata.swift */ = {
           isa = PBXFileReference; lastKnownFileType = sourcecode.swift; 
           path = PersistedMetadata.swift; sourceTree = "<group>"; };
      336      D7010BF1A1B2C3D4E5F60718 /* PaneMetadataStore.swift */ = {
           isa = PBXFileReference; lastKnownFileType = sourcecode.swift; 
           path = PaneMetadataStore.swift; sourceTree = "<group>"; };
      337 +    D7C11251A1B2C3D4E5F60718 /* SurfaceLifecycle.swift */ = {i
          +sa = PBXFileReference; lastKnownFileType = sourcecode.swift; p
          +ath = SurfaceLifecycle.swift; sourceTree = "<group>"; };      
      338      D8001BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift */ = 
           {isa = PBXFileReference; lastKnownFileType = sourcecode.swift;
            path = WorkspaceApplyPlan.swift; sourceTree = "<group>"; };
      339      D8002BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests
           .swift */ = {isa = PBXFileReference; lastKnownFileType = sourc
           ecode.swift; path = WorkspaceApplyPlanCodableTests.swift; sour
           ceTree = "<group>"; };
      340      D8003BF1A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.swift 
           */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.s
           wift; path = WorkspaceLayoutExecutor.swift; sourceTree = "<gro
           up>"; };

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      703          D70B3BF1A1B2C3D4E5F60718 /* CLIAdvisoryConnectivity.sw
           ift */,
      704          D7005BF1A1B2C3D4E5F60718 /* PersistedMetadata.swift */
           ,
      705          D7010BF1A1B2C3D4E5F60718 /* PaneMetadataStore.swift */
           ,
      706 +        D7C11251A1B2C3D4E5F60718 /* SurfaceLifecycle.swift */,
      707          D8001BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift *
           /,
      708          D8003BF1A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.sw
           ift */,
      709          D8005BF1A1B2C3D4E5F60718 /* WorkspaceSnapshot.swift */
           ,

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      1118          D70B3BF0A1B2C3D4E5F60718 /* CLIAdvisoryConnectivity.s
            wift in Sources */,
      1119          D7005BF0A1B2C3D4E5F60718 /* PersistedMetadata.swift i
            n Sources */,
      1120          D7010BF0A1B2C3D4E5F60718 /* PaneMetadataStore.swift i
            n Sources */,
      1121 +        D7C11250A1B2C3D4E5F60718 /* SurfaceLifecycle.swift in
           + Sources */,                                                 
      1122          D8001BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift 
            in Sources */,
      1123          D8003BF0A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.s
            wift in Sources */,
      1124          D8005BF0A1B2C3D4E5F60718 /* WorkspaceSnapshot.swift i
            n Sources */,

  Searched for 1 pattern (ctrl+o to expand)

⏺ Bash(xcodebuild -list -project GhosttyTabs.xcodeproj 2>&1 | head -40)
  ⎿  Command line invocation:
         /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -lis
     t -project GhosttyTabs.xcodeproj
     … +14 lines (ctrl+o to expand)

⏺ Bash(git submodule status 2>&1 | head -10; echo "---"; git submodule update
      --init vendor/bonsplit 2>&1 | tail -5)
  ⎿  -b4ef0ac2c61afa736919ad20fb24befa27839a00 ghostty
     -4d9ea33dbdb5cbdc0cef701a4153143e754786d3 homebrew-c11
     -7423a2aa3bc823ccb791301afac7301e52d9b787 vendor/bonsplit
     … +5 lines (ctrl+o to expand)

⏺ Bash(xcodebuild -list -project GhosttyTabs.xcodeproj 2>&1 | grep -A 50
      "Schemes:")
  ⎿  Running in the background (↓ to manage)

⏺ Bash(sleep 5 && cat
      /private/tmp/claude-501/-Users-atin-Projects-Stage11-code-c11-worktrees-c1
      1-25-surface-lifecycle/9cbcd465-abc2-410e-95d5-cb93ff0d5be5/tasks/bfy4x…)
  ⎿  (No output)

⏺ Bash(xcodebuild -list -project GhosttyTabs.xcodeproj 2>&1 | tail -25)  ⎿    Bonsplit: /Users/atin/Projects/Stage11/code/c11-worktrees/c11-25-sur
     face-lifecycle/vendor/bonsplit @ local
       Sentry: https://github.com/getsentry/sentry-cocoa.git @ 9.3.0
     … +23 lines (ctrl+o to expand)

⏺ Background command "List available schemes after submodule init" completed (exit code 0)

⏺ Let me run a compile check using the c11 scheme. This is a long build, so I'll
   start it in the background.

⏺ Bash(xcodebuild -scheme c11 -configuration Debug -derivedDataPath
      /tmp/c11-impl-build -skipMacroValidation build 2>&1 | tail -50)
  ⎿  Running in the background (↓ to manage)

⏺ While the build runs, let me explore more code so I'm ready for commit 2 once
  it succeeds.

  Searched for 2 patterns, read 2 files, listed 1 directory (ctrl+o to expand)

⏺ Bash(ps -p $(pgrep -f "xcodebuild.*c11.*Debug" | head -1) -o pid,etime,command
       2>&1 | head -5; echo "---"; ls -la /tmp/c11-impl-build/ 2>&1 | head -10)
  ⎿    PID ELAPSED COMMAND
     26821   01:23 /bin/zsh -c source /Users/atin/.claude/shell-snapshots/s
     napshot-zsh-1777944324197-cv94ch.sh 2>/dev/null || true && setopt NO_E
     … +10 lines (ctrl+o to expand)

⏺ Build is still resolving packages. Let me continue exploring browser code.

  Searched for 3 patterns, read 1 file (ctrl+o to expand)

⏺ Bash(ps -p $(pgrep -f "xcodebuild.*c11.*Debug" | head -1) -o pid,etime 2>&1;
      echo "---"; wc -l
      /private/tmp/claude-501/-Users-atin-Projects-Stage11-code-c11-worktree…)
  ⎿  ps: Invalid process id: -o
     ps: illegal argument: pid,etime
     usage: ps [-AaCcEefhjlMmrSTvwXx] [-O fmt | -o fmt] [-G gid[,gid...]]
     … +7 lines (ctrl+o to expand)

⏺ Background command "Compile-check c11 scheme" completed (exit code 0)

⏺ Build succeeded.

  Read 1 file (ctrl+o to expand)

⏺ GhosttyKit.xcframework missing. Let me check how to fetch it.

  Read 1 file, listed 1 directory (ctrl+o to expand)

⏺ Per CLAUDE.md "never run tests locally" and the testing policy in the prompt —
   CI handles validation. Let me do a quick syntax-only parse check, then
  commit.

⏺ Bash(xcrun swift-frontend -parse Sources/SurfaceLifecycle.swift 2>&1 | head
      -10; echo "exit=$?")
  ⎿  exit=0

⏺ Bash(xcrun swift-frontend -parse Sources/SurfaceMetadataStore.swift 2>&1 |
      head -10; echo "exit=$?")
  ⎿  exit=0

⏺ Syntax parses cleanly. Let me commit commit 1 and push to origin so CI
  validates.

⏺ Bash(git add Sources/SurfaceLifecycle.swift Sources/SurfaceMetadataStore.swift
       GhosttyTabs.xcodeproj/project.pbxproj && git status)  ⎿  On branch c11-25-surface-lifecycle
     Your branch is up to date with 'origin/main'.
     … +9 lines (ctrl+o to expand)

⏺ Bash(git commit -m "$(cat <<'EOF'
      C11-25 commit 1/9: add SurfaceLifecycleState primitive + canonical
      metadata mirror…)
  ⎿  [c11-25-surface-lifecycle 14a43a7e] C11-25 commit 1/9: add SurfaceLife
     cycleState primitive + canonical metadata mirror
      3 files changed, 175 insertions(+), 1 deletion(-)
      create mode 100644 Sources/SurfaceLifecycle.swift

⏺ Bash(git push origin c11-25-surface-lifecycle 2>&1 | tail -5)
  ⎿  remote: Create a pull request for 'c11-25-surface-lifecycle' on GitHub
      by visiting:
     remote:      https://github.com/Stage-11-Agentics/c11/pull/new/c11-25-
     … +5 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 1/9 landed: foundation — SurfaceLifecycleState primitive +
      canonical metadata key mir…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

⏺ Now commit 2. Let me check setOcclusion's scope first.

  Read 2 files (ctrl+o to expand)

⏺ Now writing commit 2 — wire terminal occlusion via lifecycle controller.

⏺ Update(Sources/SurfaceLifecycle.swift)
  ⎿  Added 8 lines, removed 1 line
      93  final class SurfaceLifecycleController {
      94      typealias Handler = (_ from: SurfaceLifecycleState, _ to: S
          urfaceLifecycleState) -> Void
      95  
      96 -    let workspaceId: UUID                                      
      96 +    private(set) var workspaceId: UUID                         
      97      let surfaceId: UUID
      98      private(set) var state: SurfaceLifecycleState
      99      private let onTransition: Handler
     ...
      110          self.onTransition = onTransition
      111      }
      112  
      113 +    /// Reparent the controller to a new workspace. Subsequent
          + metadata                                                     
      114 +    /// writes flow to the new workspace; old-workspace metada
          +ta is left                                                    
      115 +    /// alone (prunes when the surface entry closes).         
      116 +    func updateWorkspaceId(_ newWorkspaceId: UUID) {          
      117 +        self.workspaceId = newWorkspaceId                     
      118 +    }                                                         
      119 +                                                              
      120      /// Transition to `target`. Returns whether the transition
            was applied.
      121      ///
      122      /// Behavior:

⏺ Update(Sources/Panels/TerminalPanel.swift)
  ⎿  Added 6 lines
      57      /// `Workspace.toggleTextBoxMode` to detect and move focus.
      58      weak var inputTextView: InputTextView?
      59  
      60 +    /// Per-surface lifecycle controller (C11-25). Owns the can
         +onical                                                         
      61 +    /// `lifecycle_state` metadata mirror and dispatches occlus
         +ion to                                                         
      62 +    /// libghostty on state transitions. Visibility is driven f
         +rom                                                            
      63 +    /// `TerminalPanelView` via `applyVisibility(_:)`.         
      64 +    let lifecycle: SurfaceLifecycleController                  
      65 +                                                               
      66      private var cancellables = Set<AnyCancellable>()
      67  
      68      var displayTitle: String {

⏺ Update(Sources/Panels/TerminalPanel.swift)
  ⎿  Added 11 lines
       98          self.id = surface.id
       99          self.workspaceId = workspaceId
      100          self.surface = surface
      101 +        self.lifecycle = SurfaceLifecycleController(          
      102 +            workspaceId: workspaceId,                         
      103 +            surfaceId: surface.id,                            
      104 +            initial: .active                                  
      105 +        ) { [weak surface] _, target in                       
      106 +            // Pause libghostty's CVDisplayLink wakeups when t
          +he surface                                                    
      107 +            // leaves `.active`. PTY drains in every state — o
          +nly the                                                       
      108 +            // renderer is throttled. Called on workspace-sele
          +ction edge                                                    
      109 +            // events; never on the typing-latency hot path.  
      110 +            surface?.setOcclusion(target == .active)          
      111 +        }                                                     
      112  
      113          // Subscribe to surface's search state changes
      114          surface.$searchState

⏺ Update(Sources/Panels/TerminalPanel.swift)
  ⎿  Added 18 lines
      167      func updateWorkspaceId(_ newWorkspaceId: UUID) {
      168          workspaceId = newWorkspaceId
      169          surface.updateWorkspaceId(newWorkspaceId)
      170 +        lifecycle.updateWorkspaceId(newWorkspaceId)           
      171      }
      172  
      173 +    // MARK: - Lifecycle dispatch                             
      174 +                                                              
      175 +    /// Translate the panel's `isVisibleInUI` from SwiftUI int
          +o a                                                           
      176 +    /// lifecycle transition. Idempotent: calling with the sam
          +e value                                                       
      177 +    /// twice is a no-op. Called on workspace-selection edge e
          +vents                                                         
      178 +    /// (`.onChange`) and at panel mount (`.onAppear`); never 
          +on the                                                        
      179 +    /// typing-latency hot path.                              
      180 +    ///                                                       
      181 +    /// Operator-pinned states (`hibernated`) are preserved — 
          +only                                                          
      182 +    /// `active ↔ throttled` flip on automatic visibility chan
          +ges. A                                                        
      183 +    /// hibernated panel resumes via the operator's "Resume Wo
          +rkspace"                                                      
      184 +    /// action, which calls `setHibernated(false)`.           
      185 +    func applyVisibility(_ isVisibleInUI: Bool) {             
      186 +        if lifecycle.state.isOperatorPinned { return }        
      187 +        lifecycle.transition(to: isVisibleInUI ? .active : .th
          +rottled)                                                      
      188 +    }                                                         
      189 +                                                              
      190      func focus() {
      191          surface.setFocus(true)
      192          // `unfocus()` force-disables active state to stop sta
           le retries from stealing focus.

⏺ Now hook it into TerminalPanelView:

⏺ Update(Sources/Panels/TerminalPanelView.swift)
  ⎿  Added 9 lines
      142          // This prevents transient teardown/recreate that can 
           momentarily detach the hosted terminal view.
      143          .id(panel.id)
      144          .background(Color.clear)
      145 +        // C11-25: drive the per-surface lifecycle (active ↔ t
          +hrottled) from                                                
      146 +        // the same `isVisibleInUI` flag the rest of the panel
          + reads. Edge-                                                 
      147 +        // event only — onChange/onAppear, never per-keystroke
          +.                                                             
      148 +        .onAppear {                                           
      149 +            panel.applyVisibility(isVisibleInUI)              
      150 +        }                                                     
      151 +        .onChange(of: isVisibleInUI) { newValue in            
      152 +            panel.applyVisibility(newValue)                   
      153 +        }                                                     
      154      }
      155  }
      156  

⏺ Bash(xcrun swift-frontend -parse Sources/Panels/TerminalPanel.swift
      Sources/Panels/TerminalPanelView.swift Sources/SurfaceLifecycle.swift 2>&1
       | head -10; echo "exit…)
  ⎿  exit=0

⏺ Bash(git add Sources/Panels/TerminalPanel.swift
      Sources/Panels/TerminalPanelView.swift Sources/SurfaceLifecycle.swift &&
      git diff --cached --stat)
  ⎿   Sources/Panels/TerminalPanel.swift     | 35 +++++++++++++++++++++++++
     +++++++++
      Sources/Panels/TerminalPanelView.swift |  9 +++++++++
     … +2 lines (ctrl+o to expand)

⏺ Bash(git commit -m "$(cat <<'EOF'
      C11-25 commit 2/9: wire workspace-selection → terminal occlusion via
      lifecycle…)
  ⎿  [c11-25-surface-lifecycle 81e3026f] C11-25 commit 2/9: wire workspace-
     selection → terminal occlusion via lifecycle
      3 files changed, 52 insertions(+), 1 deletion(-)
     … +3 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 2/9 landed: terminal occlusion via lifecycle dispatch (DoD #3
      path) @ 81e3026f" --act…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle
⏺ For commit 3, I need to see BrowserPanel's init structure.

  Searched for 3 patterns, read 1 file (ctrl+o to expand)

⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Added 10 lines
      1862      /// The workspace ID this panel belongs to
      1863      private(set) var workspaceId: UUID
      1864  
      1865 +    /// Per-surface lifecycle controller (C11-25). Owns the c
           +anonical                                                     
      1866 +    /// `lifecycle_state` metadata mirror. Cheap-tier detach 
           +(when a                                                      
      1867 +    /// workspace is deselected, `isVisibleInUI` flips false 
           +and the                                                      
      1868 +    /// existing `WebViewRepresentable.shouldAttachWebView` g
           +ate calls                                                    
      1869 +    /// `BrowserWindowPortalRegistry.hide` — see BrowserPanel
           +View line                                                    
      1870 +    /// 6087 area) continues to be the implementation path; t
           +his                                                          
      1871 +    /// controller adds the metadata seam and is the hook the
           + ARC-grade                                                   
      1872 +    /// hibernate path replaces in C11-25 commit 5.          
      1873 +    private(set) var lifecycle: SurfaceLifecycleController!  
      1874 +                                                             
      1875      @Published private(set) var profileID: UUID
      1876      @Published private(set) var historyStore: BrowserHistoryS
            tore
      1877  

  Read 1 file (ctrl+o to expand)

⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Added 15 lines
      2566      ) {
      2567          self.id = id ?? UUID()
      2568          self.workspaceId = workspaceId
      2569 +        let panelId = self.id                                
      2570 +        self.lifecycle = SurfaceLifecycleController(         
      2571 +            workspaceId: workspaceId,                        
      2572 +            surfaceId: panelId,                              
      2573 +            initial: .active                                 
      2574 +        ) { _, _ in                                          
      2575 +            // Cheap-tier detach is auto-driven by the existi
           +ng                                                           
      2576 +            // `WebViewRepresentable.shouldAttachWebView` gat
           +e in                                                         
      2577 +            // BrowserPanelView (~line 6087). The lifecycle c
           +ontroller                                                    
      2578 +            // mirrors the canonical `lifecycle_state` metada
           +ta key so                                                    
      2579 +            // the sidebar / `c11 tree --json` / snapshot can
           + observe                                                     
      2580 +            // the state. C11-25 commit 5 replaces this handl
           +er with                                                      
      2581 +            // snapshot+terminate dispatch when the target is
      2582 +            // `.hibernated` (ARC-grade tier).               
      2583 +        }                                                    
      2584          let requestedProfileID = profileID ?? BrowserProfileS
            tore.shared.effectiveLastUsedProfileID
      2585          let resolvedProfileID = BrowserProfileStore.shared.pr
            ofileDefinition(id: requestedProfileID) != nil
      2586              ? requestedProfileID

⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Added 14 lines
      2762  
      2763      func updateWorkspaceId(_ newWorkspaceId: UUID) {
      2764          workspaceId = newWorkspaceId
      2765 +        lifecycle.updateWorkspaceId(newWorkspaceId)          
      2766      }
      2767  
      2768 +    // MARK: - Lifecycle dispatch                            
      2769 +                                                             
      2770 +    /// Translate the panel's `isVisibleInUI` from SwiftUI in
           +to a lifecycle                                               
      2771 +    /// transition. Idempotent; called on workspace-selection
           + edge events                                                 
      2772 +    /// (`.onChange`) and at panel mount (`.onAppear`). Opera
           +tor-pinned                                                   
      2773 +    /// `hibernated` is preserved — only `active ↔ throttled`
           + flips on                                                    
      2774 +    /// auto-visibility changes.                             
      2775 +    func applyVisibility(_ isVisibleInUI: Bool) {            
      2776 +        if lifecycle.state.isOperatorPinned { return }       
      2777 +        lifecycle.transition(to: isVisibleInUI ? .active : .t
           +hrottled)                                                    
      2778 +    }                                                        
      2779 +                                                             
      2780      func reattachToWorkspace(
      2781          _ newWorkspaceId: UUID,
      2782          isRemoteWorkspace: Bool,
     ...
      2785          remoteStatus: BrowserRemoteWorkspaceStatus?
      2786      ) {
      2787          workspaceId = newWorkspaceId
      2788 +        lifecycle.updateWorkspaceId(newWorkspaceId)          
      2789          usesRemoteWorkspaceProxy = isRemoteWorkspace
      2790          let targetStore = isRemoteWorkspace
      2791              ? WKWebsiteDataStore(forIdentifier: remoteWebsite
            DataStoreIdentifier ?? newWorkspaceId)

⏺ Now hook it into BrowserPanelView. Let me find a good place to add the
  .onAppear / .onChange modifiers — likely near the existing .onChange(of: 
  isVisibleInUI).

  Read 1 file (ctrl+o to expand)

⏺ Update(Sources/Panels/BrowserPanelView.swift)
  ⎿  Added 9 lines
      674              }
      675          }
      676          .onChange(of: isVisibleInUI) { visibleInUI in
      677 +            // C11-25: drive per-surface lifecycle (active ↔ t
          +hrottled) from                                                
      678 +            // the same flag the rest of the panel reads. Edge
          +-event only.                                                  
      679 +            panel.applyVisibility(visibleInUI)                
      680              if visibleInUI {
      681                  panel.cancelPendingDeveloperToolsVisibilityLos
           sCheck()
      682                  return
     ...
      686              // an attached-inspector X-close.
      687              panel.scheduleDeveloperToolsVisibilityLossCheck()
      688          }
      689 +        .onAppear {                                           
      690 +            // C11-25: seed the lifecycle state from the initi
          +al visibility at                                              
      691 +            // panel mount. Workspaces created in the backgrou
          +nd mount with                                                 
      692 +            // `isVisibleInUI == false` and want to start in `
          +.throttled`.                                                  
      693 +            panel.applyVisibility(isVisibleInUI)              
      694 +        }                                                     
      695          .onChange(of: isFocused) { focused in
      696  #if DEBUG
      697              logBrowserFocusState(

⏺ Bash(xcrun swift-frontend -parse Sources/Panels/BrowserPanel.swift
      Sources/Panels/BrowserPanelView.swift 2>&1 | head -10; echo "exit=$?")
  ⎿  exit=0

⏺ Bash(git add Sources/Panels/BrowserPanel.swift
      Sources/Panels/BrowserPanelView.swift && git diff --cached --stat && git
      commit -m "$(cat <<'EOF'
      C11-25 commit 3/9: w…)
  ⎿   Sources/Panels/BrowserPanel.swift     | 39 ++++++++++++++++++++++++++
     +++++++++
      Sources/Panels/BrowserPanelView.swift |  9 ++++++++
     … +7 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 3/9 landed: browser cheap-tier lifecycle wiring (DoD #1 path) @
      bc19e374" --actor "ag…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

⏺ I need to refactor BrowserPanel's lifecycle handler to capture self and
  publish state for SwiftUI. Let me look at how to make the lifecycle state
  observable.

  Searched for 1 pattern, read 1 file (ctrl+o to expand)

⏺ Let me restructure to move the lifecycle init to the end of BrowserPanel.init
  so [weak self] works.

⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Removed 15 lines
      2566      ) {
      2567          self.id = id ?? UUID()
      2568          self.workspaceId = workspaceId
      2569 -        let panelId = self.id                                
      2570 -        self.lifecycle = SurfaceLifecycleController(         
      2571 -            workspaceId: workspaceId,                        
      2572 -            surfaceId: panelId,                              
      2573 -            initial: .active                                 
      2574 -        ) { _, _ in                                          
      2575 -            // Cheap-tier detach is auto-driven by the existi
           -ng                                                           
      2576 -            // `WebViewRepresentable.shouldAttachWebView` gat
           -e in                                                         
      2577 -            // BrowserPanelView (~line 6087). The lifecycle c
           -ontroller                                                    
      2578 -            // mirrors the canonical `lifecycle_state` metada
           -ta key so                                                    
      2579 -            // the sidebar / `c11 tree --json` / snapshot can
           - observe                                                     
      2580 -            // the state. C11-25 commit 5 replaces this handl
           -er with                                                      
      2581 -            // snapshot+terminate dispatch when the target is
      2582 -            // `.hibernated` (ARC-grade tier).               
      2583 -        }                                                    
      2569          let requestedProfileID = profileID ?? BrowserProfileS
            tore.shared.effectiveLastUsedProfileID
      2570          let resolvedProfileID = BrowserProfileStore.shared.pr
            ofileDefinition(id: requestedProfileID) != nil
      2571              ? requestedProfileID

⏺ Update(Sources/Panels/BrowserPanel.swift)  ⎿  Added 16 lines
      2679              self?.webView.window ?? NSApp.keyWindow ?? NSApp.
            mainWindow
      2680          }
      2681  
      2682 +        // Initialize the per-surface lifecycle controller AF
           +TER all stored                                               
      2683 +        // properties are set so the handler can capture `sel
           +f` weakly.                                                   
      2684 +        // C11-25: cheap-tier detach is auto-driven by the ex
           +isting                                                       
      2685 +        // `WebViewRepresentable.shouldAttachWebView` gate in
           + BrowserPanelView                                            
      2686 +        // (~line 6087). The controller mirrors the canonical
           + `lifecycle_state`                                           
      2687 +        // metadata key and updates `lifecycleState` for Swif
           +tUI re-render.                                               
      2688 +        // The C11-25 commit 5 hibernate path extends this ha
           +ndler with                                                   
      2689 +        // snapshot+terminate dispatch when the target is `.h
           +ibernated`.                                                  
      2690 +        self.lifecycle = SurfaceLifecycleController(         
      2691 +            workspaceId: workspaceId,                        
      2692 +            surfaceId: self.id,                              
      2693 +            initial: .active                                 
      2694 +        ) { [weak self] _, target in                         
      2695 +            self?.lifecycleState = target                    
      2696 +        }                                                    
      2697 +                                                             
      2698          // Navigate to initial URL if provided
      2699          if let url = initialURL {
      2700              shouldRenderWebView = true

⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Added 8 lines
      1870      /// 6087 area) continues to be the implementation path; t
            his
      1871      /// controller adds the metadata seam and is the hook the
             ARC-grade
      1872      /// hibernate path replaces in C11-25 commit 5.
      1873 +    ///                                                      
      1874 +    /// IUO because it's set at the end of `init` once all ot
           +her stored                                                   
      1875 +    /// properties are assigned, so the handler can capture `
           +[weak self]`.                                                
      1876      private(set) var lifecycle: SurfaceLifecycleController!
      1877  
      1878 +    /// Published mirror of `lifecycle.state` so SwiftUI can 
           +re-render                                                    
      1879 +    /// (e.g. swap the live WKWebView for a placeholder NSIma
           +ge when                                                      
      1880 +    /// hibernated). Updated by the lifecycle controller's ha
           +ndler.                                                       
      1881 +    @Published private(set) var lifecycleState: SurfaceLifecy
           +cleState = .active                                           
      1882 +                                                             
      1883      @Published private(set) var profileID: UUID
      1884      @Published private(set) var historyStore: BrowserHistoryS
            tore
      1885  

⏺ Now let me create BrowserSnapshotStore.swift.

⏺ Write(Sources/BrowserSnapshotStore.swift)
  ⎿  Wrote 206 lines to Sources/BrowserSnapshotStore.swift
       2 import Foundation
       3 import WebKit
       4 
       5 /// Per-surface snapshot of a hibernated browser surface.
       6 ///
         anel canured before the WebContent process is torn down so the p
       8 /// render a placeholder image (instead of a blank rectangle) un
         til the
       9 /// operator resumes the workspace.
      10 ///
     … +246 lines (ctrl+o to expand)

⏺ Add BrowserSnapshotStore.swift to the Xcode project, then wire the placeholder
   render path.

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      27      D7005BF0A1B2C3D4E5F60718 /* PersistedMetadata.swift in Sour
          ces */ = {isa = PBXBuildFile; fileRef = D7005BF1A1B2C3D4E5F6071
          8 /* PersistedMetadata.swift */; };
      28      D7010BF0A1B2C3D4E5F60718 /* PaneMetadataStore.swift in Sour
          ces */ = {isa = PBXBuildFile; fileRef = D7010BF1A1B2C3D4E5F6071
          8 /* PaneMetadataStore.swift */; };
      29      D7C11250A1B2C3D4E5F60718 /* SurfaceLifecycle.swift in Sourc
          es */ = {isa = PBXBuildFile; fileRef = D7C11251A1B2C3D4E5F60718
           /* SurfaceLifecycle.swift */; };
      30 +    D7C11252A1B2C3D4E5F60718 /* BrowserSnapshotStore.swift in S
         +ources */ = {isa = PBXBuildFile; fileRef = D7C11253A1B2C3D4E5F6
         +0718 /* BrowserSnapshotStore.swift */; };                      
      31      D8001BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift in Sou
          rces */ = {isa = PBXBuildFile; fileRef = D8001BF1A1B2C3D4E5F607
          18 /* WorkspaceApplyPlan.swift */; };
      32      D8002BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests.
          swift in Sources */ = {isa = PBXBuildFile; fileRef = D8002BF1A1
          B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests.swift */; };
      33      D8003BF0A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.swift i
          n Sources */ = {isa = PBXBuildFile; fileRef = D8003BF1A1B2C3D4E
          5F60718 /* WorkspaceLayoutExecutor.swift */; };

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      336      D7005BF1A1B2C3D4E5F60718 /* PersistedMetadata.swift */ = {
           isa = PBXFileReference; lastKnownFileType = sourcecode.swift; 
           path = PersistedMetadata.swift; sourceTree = "<group>"; };
      337      D7010BF1A1B2C3D4E5F60718 /* PaneMetadataStore.swift */ = {
           isa = PBXFileReference; lastKnownFileType = sourcecode.swift; 
           path = PaneMetadataStore.swift; sourceTree = "<group>"; };
      338      D7C11251A1B2C3D4E5F60718 /* SurfaceLifecycle.swift */ = {i
           sa = PBXFileReference; lastKnownFileType = sourcecode.swift; p
           ath = SurfaceLifecycle.swift; sourceTree = "<group>"; };
      339 +    D7C11253A1B2C3D4E5F60718 /* BrowserSnapshotStore.swift */ 
          += {isa = PBXFileReference; lastKnownFileType = sourcecode.swif
          +t; path = BrowserSnapshotStore.swift; sourceTree = "<group>"; 
          +};                                                            
      340      D8001BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift */ = 
           {isa = PBXFileReference; lastKnownFileType = sourcecode.swift;
            path = WorkspaceApplyPlan.swift; sourceTree = "<group>"; };
      341      D8002BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests
           .swift */ = {isa = PBXFileReference; lastKnownFileType = sourc
           ecode.swift; path = WorkspaceApplyPlanCodableTests.swift; sour
           ceTree = "<group>"; };
      342      D8003BF1A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.swift 
           */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.s
           wift; path = WorkspaceLayoutExecutor.swift; sourceTree = "<gro
           up>"; };

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      706          D7005BF1A1B2C3D4E5F60718 /* PersistedMetadata.swift */
           ,
      707          D7010BF1A1B2C3D4E5F60718 /* PaneMetadataStore.swift */
           ,
      708          D7C11251A1B2C3D4E5F60718 /* SurfaceLifecycle.swift */,
      709 +        D7C11253A1B2C3D4E5F60718 /* BrowserSnapshotStore.swift
          + */,                                                          
      710          D8001BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift *
           /,
      711          D8003BF1A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.sw
           ift */,
      712          D8005BF1A1B2C3D4E5F60718 /* WorkspaceSnapshot.swift */
           ,

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      1122          D7005BF0A1B2C3D4E5F60718 /* PersistedMetadata.swift i
            n Sources */,
      1123          D7010BF0A1B2C3D4E5F60718 /* PaneMetadataStore.swift i
            n Sources */,
      1124          D7C11250A1B2C3D4E5F60718 /* SurfaceLifecycle.swift in
             Sources */,
      1125 +        D7C11252A1B2C3D4E5F60718 /* BrowserSnapshotStore.swif
           +t in Sources */,                                             
      1126          D8001BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift 
            in Sources */,
      1127          D8003BF0A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.s
            wift in Sources */,
      1128          D8005BF0A1B2C3D4E5F60718 /* WorkspaceSnapshot.swift i
            n Sources */,

⏺ Now the placeholder render path in BrowserPanelView. Let me look at the
  webView property's full structure.

  Read 1 file (ctrl+o to expand)

⏺ Update(Sources/Panels/BrowserPanelView.swift)
  ⎿  Added 15 lines, removed 1 line
      1187              isCurrentPaneOwner
      1188  
      1189          return Group {
      1190 -            if panel.shouldRenderWebView {                   
      1190 +            if panel.lifecycleState == .hibernated {         
      1191 +                // C11-25 ARC-grade tier: the WebContent proc
           +ess has been                                                 
      1192 +                // released for this surface. Render the cach
           +ed snapshot                                                  
      1193 +                // (or a neutral background if the snapshot i
           +s missing,                                                   
      1194 +                // e.g. after a c11 restart). The placeholder
           + swaps back                                                  
      1195 +                // to the live WKWebView when the operator re
           +sumes the                                                    
      1196 +                // workspace and the lifecycle transitions ba
           +ck to                                                        
      1197 +                // `.active`. The state mirror is `@Published
           +` on                                                         
      1198 +                // BrowserPanel so SwiftUI re-renders on tran
           +sition.                                                      
      1199 +                BrowserHibernatedPlaceholderView(            
      1200 +                    surfaceId: panel.id,                     
      1201 +                    backgroundColor: Color(nsColor: browserCh
           +romeBackgroundColor)                                         
      1202 +                )                                            
      1203 +                .accessibilityIdentifier("BrowserHibernatedPl
           +aceholder")                                                  
      1204 +            } else if panel.shouldRenderWebView {            
      1205                  WebViewRepresentable(
      1206                      panel: panel,
      1207                      paneId: paneId,

  Read 1 file (ctrl+o to expand)

⏺ Update(Sources/Panels/BrowserPanelView.swift)
  ⎿  Added 27 lines
      6487          )
      6488      }
      6489  }
      6490 +                                                             
      6491 +// MARK: - C11-25 hibernated browser placeholder             
      6492 +                                                             
      6493 +/// SwiftUI placeholder rendered in place of a live WKWebView
           + when a                                                      
      6494 +/// browser surface is in the `.hibernated` lifecycle state. 
           +Pulls the                                                    
      6495 +/// captured NSImage snapshot from `BrowserSnapshotStore`; if
           + the cache                                                   
      6496 +/// is empty (e.g. workspace restored from disk before a snap
           +shot was                                                     
      6497 +/// re-captured), falls back to a neutral background tinted t
           +o the                                                        
      6498 +/// browser's current chrome color.                          
      6499 +private struct BrowserHibernatedPlaceholderView: View {      
      6500 +    let surfaceId: UUID                                      
      6501 +    let backgroundColor: Color                               
      6502 +                                                             
      6503 +    var body: some View {                                    
      6504 +        ZStack {                                             
      6505 +            backgroundColor                                  
      6506 +            if let snapshot = BrowserSnapshotStore.shared.sna
           +pshot(forSurfaceId: surfaceId),                              
      6507 +               let image = snapshot.image {                  
      6508 +                Image(nsImage: image)                        
      6509 +                    .resizable()                             
      6510 +                    .aspectRatio(contentMode: .fill)         
      6511 +                    .clipped()                               
      6512 +            }                                                
      6513 +        }                                                    
      6514 +        .contentShape(Rectangle())                           
      6515 +    }                                                        
      6516 +}                                                            

⏺ Bash(xcrun swift-frontend -parse Sources/BrowserSnapshotStore.swift
      Sources/Panels/BrowserPanel.swift Sources/Panels/BrowserPanelView.swift
      2>&1 | head -20; echo "ex…)
  ⎿  exit=0

⏺ Bash(git add Sources/BrowserSnapshotStore.swift
      Sources/Panels/BrowserPanel.swift Sources/Panels/BrowserPanelView.swift
      GhosttyTabs.xcodeproj/project.pbxproj && git…)
  ⎿   GhosttyTabs.xcodeproj/project.pbxproj |   4 +
      Sources/BrowserSnapshotStore.swift    | 206 +++++++++++++++++++++++++
     +++++++++
     … +3 lines (ctrl+o to expand)

⏺ Bash(git commit -m "$(cat <<'EOF'
      C11-25 commit 4/9: browser snapshot+terminate plumbing (ARC-grade)…)
  ⎿  [c11-25-surface-lifecycle 8ee4d61f] C11-25 commit 4/9: browser snapsho
     t+terminate plumbing (ARC-grade)
      4 files changed, 276 insertions(+), 16 deletions(-)
     … +4 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 4/9 landed: ARC-grade snapshot+terminate plumbing
      (BrowserSnapshotStore, _webProcessI…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

⏺ Now commit 5: wire the hibernate dispatch. Let me update the BrowserPanel
  handler.

⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Added 6 lines, removed 5 lines
      2692          // C11-25: cheap-tier detach is auto-driven by the ex
            isting
      2693          // `WebViewRepresentable.shouldAttachWebView` gate in
             BrowserPanelView
      2694          // (~line 6087). The controller mirrors the canonical
             `lifecycle_state`
      2695 -        // metadata key and updates `lifecycleState` for Swif
           -tUI re-render.                                               
      2696 -        // The C11-25 commit 5 hibernate path extends this ha
           -ndler with                                                   
      2697 -        // snapshot+terminate dispatch when the target is `.h
           -ibernated`.                                                  
      2695 +        // metadata key, updates `lifecycleState` for SwiftUI
           + re-render, and                                              
      2696 +        // dispatches snapshot+terminate on the ARC-grade hib
           +ernate path.                                                 
      2697          self.lifecycle = SurfaceLifecycleController(
      2698              workspaceId: workspaceId,
      2699              surfaceId: self.id,
      2700              initial: .active
      2702 -        ) { [weak self] _, target in                         
      2703 -            self?.lifecycleState = target                    
      2701 +        ) { [weak self] from, target in                      
      2702 +            guard let self else { return }                   
      2703 +            self.lifecycleState = target                     
      2704 +            self.dispatchLifecycleTransition(from: from, to: 
           +target)                                                      
      2705          }
      2706  
      2707          // Navigate to initial URL if provided
⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Added 102 lines
      2787          lifecycle.transition(to: isVisibleInUI ? .active : .t
            hrottled)
      2788      }
      2789  
      2790 +    /// Operator-driven transition into / out of `.hibernated
           +`. Invoked                                                   
      2791 +    /// from `TabManager.hibernateWorkspace` / `resumeWorkspa
           +ce`                                                          
      2792 +    /// (C11-25 commit 7). Hibernating captures the current s
           +napshot                                                      
      2793 +    /// and tears down the WebContent process; resuming refir
           +es                                                           
      2794 +    /// `load(URLRequest:)` against the captured URL.        
      2795 +    func setHibernated(_ on: Bool) {                         
      2796 +        if on {                                              
      2797 +            lifecycle.transition(to: .hibernated)            
      2798 +        } else if lifecycle.state == .hibernated {           
      2799 +            lifecycle.transition(to: .active)                
      2800 +        }                                                    
      2801 +    }                                                        
      2802 +                                                             
      2803 +    /// React to a lifecycle transition. Called from the cont
           +roller's                                                     
      2804 +    /// handler closure, which already updated `lifecycleStat
           +e`. Splits                                                   
      2805 +    /// the work by transition direction:                    
      2806 +    ///                                                      
      2807 +    /// - `* → .hibernated`: capture snapshot, then release t
           +he live                                                      
      2808 +    ///   WKWebView so ARC reaps the WebContent process. The 
           +panel's                                                      
      2809 +    ///   `webView` is replaced with a fresh, unloaded WKWebV
           +iew; the                                                     
      2810 +    ///   body branches to `BrowserHibernatedPlaceholderView`
           + until                                                       
      2811 +    ///   resume.                                            
      2812 +    /// - `.hibernated → .active`: read the captured snapshot
           +'s URL                                                       
      2813 +    ///   and refire `navigate(to:)`. Cookies survive because
           + the                                                         
      2814 +    ///   `WKHTTPCookieStore` lives at the process-pool level
           +.                                                            
      2815 +    ///   Best-effort scroll restore is deferred (operator ac
           +cepted in                                                    
      2816 +    ///   §0a of the C11-25 plan).                           
      2817 +    /// - `* → .throttled`, `.throttled → .active`: cheap-tie
           +r detach                                                     
      2818 +    ///   is auto-driven by the existing `shouldAttachWebView
           +` gate;                                                      
      2819 +    ///   no extra dispatch needed here.                     
      2820 +    /// - `* → .suspended`: not entered in C11-25.           
      2821 +    private func dispatchLifecycleTransition(                
      2822 +        from: SurfaceLifecycleState,                         
      2823 +        to target: SurfaceLifecycleState                     
      2824 +    ) {                                                      
      2825 +        switch (from, target) {                              
      2826 +        case (let prior, .hibernated) where prior != .hiberna
           +ted:                                                         
      2827 +            performHibernate()                               
      2828 +        case (.hibernated, .active):                         
      2829 +            performResumeFromHibernate()                     
      2830 +        default:                                             
      2831 +            break                                            
      2832 +        }                                                    
      2833 +    }                                                        
      2834 +                                                             
      2835 +    /// ARC-grade hibernate. Captures a snapshot of the curre
           +nt page,                                                     
      2836 +    /// then replaces the WKWebView with a fresh inert one an
           +d releases                                                   
      2837 +    /// the prior reference so ARC reaps the WebContent proce
           +ss. The                                                      
      2838 +    /// panel's body branches to placeholder via `lifecycleSt
           +ate`.                                                        
      2839 +    private func performHibernate() {                        
      2840 +        let liveWebView = webView                            
      2841 +        BrowserSnapshotStore.shared.capture(                 
      2842 +            surfaceId: self.id,                              
      2843 +            webView: liveWebView                             
      2844 +        ) { [weak self] _ in                                 
      2845 +            guard let self else { return }                   
      2846 +            self.replaceWebViewForHibernate(oldWebView: liveW
           +ebView)                                                      
      2847 +        }                                                    
      2848 +    }                                                        
      2849 +                                                             
      2850 +    /// Resume from hibernate. The WKWebView is fresh-and-emp
           +ty (was                                                      
      2851 +    /// replaced during hibernate) — refire `navigate(to:)` w
           +ith the                                                      
      2852 +    /// snapshot's URL so the WebContent process spins back u
           +p. Drops                                                     
      2853 +    /// the cached snapshot once the navigation is initiated.
      2854 +    private func performResumeFromHibernate() {              
      2855 +        let snapshot = BrowserSnapshotStore.shared.snapshot(f
           +orSurfaceId: self.id)                                        
      2856 +        BrowserSnapshotStore.shared.clear(forSurfaceId: self.
           +id)                                                          
      2857 +        if let url = snapshot?.url {                         
      2858 +            shouldRenderWebView = true                       
      2859 +            navigate(to: url)                                
      2860 +        }                                                    
      2861 +    }                                                        
      2862 +                                                             
      2863 +    /// Hibernate-time companion to `replaceWebViewPreserving
           +State`.                                                      
      2864 +    /// Tears down the live WKWebView (graceful: stopLoading 
           ++ delegates                                                  
      2865 +    /// nil + portal detach + ARC release via reference repla
           +cement)                                                      
      2866 +    /// and installs a fresh inert webview in its place. Unli
           +ke the                                                       
      2867 +    /// post-crash variant, the new webview is NOT loaded wit
           +h the                                                        
      2868 +    /// original URL — the panel renders a placeholder until 
           +resume.                                                      
      2869 +    private func replaceWebViewForHibernate(oldWebView: WKWeb
           +View) {                                                      
      2870 +        guard oldWebView === webView else { return }         
      2871 +        webViewObservers.removeAll()                         
      2872 +        webViewCancellables.removeAll()                      
      2873 +        faviconTask?.cancel()                                
      2874 +        faviconTask = nil                                    
      2875 +        BrowserWindowPortalRegistry.detach(webView: oldWebVie
           +w)                                                           
      2876 +        BrowserWebContentTerminator.tearDownGracefully(oldWeb
           +View)                                                        
      2877 +                                                             
      2878 +        let replacement = Self.makeWebView(                  
      2879 +            profileID: profileID,                            
      2880 +            websiteDataStore: websiteDataStore               
      2881 +        )                                                    
      2882 +        webViewInstanceID = UUID()                           
      2883 +        webView = replacement                                
      2884 +        // Don't bind the replacement to the portal — the bod
           +y branches                                                   
      2885 +        // to placeholder while hibernated, and binding would
      2886 +        // unnecessarily reach for portal hosts that the plac
           +eholder                                                      
      2887 +        // doesn't use. Resume calls navigate(to:) which sets
           + up the                                                      
      2888 +        // attachment via the regular shouldAttachWebView pat
           +h once                                                       
      2889 +        // lifecycleState flips back to .active.             
      2890 +    }                                                        
      2891 +                                                             
      2892      func reattachToWorkspace(
      2893          _ newWorkspaceId: UUID,
      2894          isRemoteWorkspace: Bool,

  Searched for 1 pattern (ctrl+o to expand)

⏺ Bash(xcrun swift-frontend -parse Sources/Panels/BrowserPanel.swift
      Sources/BrowserSnapshotStore.swift 2>&1 | head -10; echo "exit=$?")
  ⎿  exit=0

⏺ Bash(git add Sources/Panels/BrowserPanel.swift && git diff --cached --stat &&
      git commit -m "$(cat <<'EOF'
      C11-25 commit 5/9: wire hibernated → ARC-grade browser sna…)
  ⎿   Sources/Panels/BrowserPanel.swift | 113 +++++++++++++++++++++++++++++
     +++++++--
      1 file changed, 108 insertions(+), 5 deletions(-)
     … +6 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 5/9 landed: ARC-grade hibernate dispatch wired (DoD #2 path) @
      3a06426f" --actor "age…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

⏺ Commit 6 — sampler. Let me check what PID accessors exist for terminals.

  Searched for 12 patterns, read 1 file, listed 2 directories (ctrl+o to expand)

⏺ Let me write the SurfaceMetricsSampler in a focused form that delivers DoD #5
  for browsers and stubs terminals.

⏺ Write(Sources/SurfaceMetricsSampler.swift)
  ⎿  Wrote 267 lines to Sources/SurfaceMetricsSampler.swift
       2 import Combineion
       3 import Darwin
       4 
       6 /// Per-surface CPU/RSS sampler. C11-25 commit 6.
       7 /// Runs on a background `DispatchSourceTimer` at a fixed cadenc
         e (default
       9 /// `c11.surfaceMetrics.sampleHz`). On each tick it walks every 
         registered
      10 /// surface, resolves the surface's process identifier via the r
         egistered
     … +313 lines (ctrl+o to expand)

⏺ Let me refactor SurfaceMetricsSampler — the MainActor gymnastics are messy.
  Make it @unchecked Sendable with explicit locking instead.

⏺ Write(Sources/SurfaceMetricsSampler.swift)
  ⎿  Added 38 lines, removed 91 lines
      12  /// cumulative CPU time + resident-size bytes. CPU% is derived 
          from the
      13  /// inter-tick CPU-time delta against the inter-tick wall-clock
           delta.
      14  ///
      15 -/// Threading: registrations + sample reads are protected by an
      16 -/// `os_unfair_lock`. The timer fires off-main; the sidebar rea
         -ds samples                                                     
      17 -/// via `let` projection during body eval. The published `revis
         -ion`                                                           
      18 -/// counter is bumped on the main queue after each tick so Swif
         -tUI                                                            
      19 -/// re-evaluates the sidebar at the cadence — `TabItemView.==` 
         -catches                                                        
      20 -/// unchanged metric values and short-circuits body re-eval, pr
         -eserving                                                       
      21 -/// the typing-latency invariant.                              
      15 +/// Threading: the sampler is not `@MainActor` — its state is p
         +rotected                                                       
      16 +/// by an `os_unfair_lock`, and the timer fires off-main. The `
         +@Published                                                     
      17 +/// revision` counter is bumped on the main queue after each ti
         +ck so                                                          
      18 +/// SwiftUI re-evaluates the sidebar at the cadence —          
      19 +/// `TabItemView.==` catches unchanged metric values and short-
         +circuits                                                       
      20 +/// body re-eval, preserving the typing-latency invariant.     
      21  ///
      22  /// PID resolution differs by surface kind:
      23  ///
     ...
      29  ///   this is a follow-up; for C11-25 commit 6 the terminal pan
          el
      30  ///   registers a provider that returns `nil`, the sidebar rend
          ers `—`
      31  ///   for terminal CPU/RSS.
      33 -@MainActor                                                     
      34 -final class SurfaceMetricsSampler: ObservableObject {          
      32 +final class SurfaceMetricsSampler: ObservableObject, @unchecked
         + Sendable {                                                    
      33      static let shared = SurfaceMetricsSampler()
      34  
      35      /// Per-surface sample. Stored briefly between ticks; consu
          mers read
     ...
       64  
       65      /// Begin sampling. Idempotent.
       66      func start() {
       69 -        guard timer == nil else { return }                    
       70 -        let hz = max(1.0, min(10.0, Self.configuredHz()))     
       71 -        let intervalMs = Int(1000.0 / hz)                     
       67 +        // Construct timer off-main; idempotency check is lock
          +ed.                                                           
       68 +        let intervalMs: Int = {                               
       69 +            let hz = max(1.0, min(10.0, Self.configuredHz())) 
       70 +            return Int(1000.0 / hz)                           
       71 +        }()                                                   
       72 +        os_unfair_lock_lock(lock)                             
       73 +        guard timer == nil else {                             
       74 +            os_unfair_lock_unlock(lock)                       
       75 +            return                                            
       76 +        }                                                     
       77          let timer = DispatchSource.makeTimerSource(queue: queu
           e)
       78          timer.schedule(
       79              deadline: .now() + .milliseconds(intervalMs),
       80              repeating: .milliseconds(intervalMs)
       81          )
       82 +        self.timer = timer                                    
       83 +        os_unfair_lock_unlock(lock)                           
       84          timer.setEventHandler { [weak self] in
       85              self?.tick()
       86          }
       87          timer.resume()
       81 -        self.timer = timer                                    
       88      }
       89  
       90      /// Stop sampling. Used in tests.
       91      func stop() {
       86 -        timer?.cancel()                                       
       92 +        os_unfair_lock_lock(lock)                             
       93 +        let t = timer                                         
       94          timer = nil
       95 +        os_unfair_lock_unlock(lock)                           
       96 +        t?.cancel()                                           
       97      }
       98  
       99      /// Register a surface + PID provider. The provider is inv
           oked off-main
      100      /// during sampling; it must be thread-safe (or read state
            that is).
       92 -    /// Browser panels pass `{ [weak self] in self?.webView.c1
          -1_webProcessIdentifier }`;                                    
       93 -    /// terminal panels pass `{ nil }` for C11-25 (see TODO ab
          -ove).                                                         
      101 +    /// Browser panels pass a closure that reads              
      102 +    /// `webView.c11_webProcessIdentifier` (KVC, safe off-main
          +); terminal                                                   
      103 +    /// panels pass `{ nil }` for C11-25.                     
      104      func register(surfaceId: UUID, pidProvider: @escaping () -
           > pid_t?) {
      105          os_unfair_lock_lock(lock)
      106          pidProviders[surfaceId] = pidProvider
     ...
      139  
      140      // MARK: - Sampling tick
      141  
      132 -    private nonisolated func tick() {                         
      142 +    private func tick() {                                     
      143          let now = Date()
      134 -        let lockPtr = self.lockUnsafe                         
      135 -        os_unfair_lock_lock(lockPtr)                          
      136 -        let providers = self.pidProvidersUnsafe               
      137 -        let priorTimes = self.lastCpuTimesUnsafe              
      138 -        let prior = self.lastSampleAtUnsafe                   
      139 -        os_unfair_lock_unlock(lockPtr)                        
      144 +        os_unfair_lock_lock(lock)                             
      145 +        let providers = pidProviders                          
      146 +        let priorTimes = lastCpuTimes                         
      147 +        let prior = lastSampleAt                              
      148 +        os_unfair_lock_unlock(lock)                           
      149  
      150          let dt: Double = prior.map { now.timeIntervalSince($0)
            } ?? 0
      151          var newSamples: [UUID: Sample] = [:]
      152          var newTimes: [pid_t: UInt64] = [:]
      153  
      154          for (surfaceId, provider) in providers {
      146 -            // The provider is captured off-main; if it touche
          -s main-actor                                                  
      147 -            // state the call site is responsible for the mars
          -halling.                                                      
      148 -            // Browser providers read `c11_webProcessIdentifie
          -r` which is                                                   
      149 -            // KVC against a WKWebView property — marked @Main
          -Actor in                                                      
      150 -            // recent SDKs but historically callable off-main.
          - Wrap in a                                                    
      151 -            // sync hop to main if the SDK enforces.          
      152 -            let pid = Self.resolvePidSafely(provider)         
      153 -            guard let pid else { continue }                   
      155 +            guard let pid = provider() else { continue }      
      156              guard let cumulative = Self.proc_pid_cumulative_cp
           u_ns(pid) else { continue }
      157              let rssBytes = Self.proc_pid_rss_bytes(pid) ?? 0
      158  
     ...
      171              )
      172          }
      173  
      172 -        os_unfair_lock_lock(lockPtr)                          
      173 -        self.samplesUnsafe = newSamples                       
      174 -        self.lastCpuTimesUnsafe = newTimes                    
      175 -        self.lastSampleAtUnsafe = now                         
      176 -        os_unfair_lock_unlock(lockPtr)                        
      174 +        os_unfair_lock_lock(lock)                             
      175 +        samples = newSamples                                  
      176 +        lastCpuTimes = newTimes                               
      177 +        lastSampleAt = now                                    
      178 +        os_unfair_lock_unlock(lock)                           
      179  
      180          // Bump revision on main so SwiftUI re-evaluates the s
           idebar.
      181          DispatchQueue.main.async { [weak self] in
     ...
      183          }
      184      }
      185  
      184 -    // MARK: - Off-main accessors (lock-protected; nonisolated
          - to dodge MainActor)                                          
      185 -                                                              
      186 -    private nonisolated var lockUnsafe: UnsafeMutablePointer<o
          -s_unfair_lock_s> {                                            
      187 -        // The lock pointer is set once in init and never reas
          -signed; safe                                                  
      188 -        // to read off-main without isolation.                
      189 -        return _unsafeUnwrappedLock()                         
      190 -    }                                                         
      191 -    private nonisolated func _unsafeUnwrappedLock() -> UnsafeM
          -utablePointer<os_unfair_lock_s> {                             
      192 -        // Bridge the @MainActor-annotated `lock` through an u
          -nchecked                                                      
      193 -        // accessor. Reads only; no mutation of MainActor stat
          -e.                                                            
      194 -        return Unmanaged.passUnretained(self).takeUnretainedVa
          -lue().lockBacking                                             
      195 -    }                                                         
      196 -                                                              
      197 -    /// MainActor-isolated backing accessor for `lock`. Used o
          -nly by the                                                    
      198 -    /// nonisolated bridge above.                             
      199 -    private var lockBacking: UnsafeMutablePointer<os_unfair_lo
          -ck_s> { lock }                                                
      200 -                                                              
      201 -    private nonisolated var pidProvidersUnsafe: [UUID: () -> p
          -id_t?] {                                                      
      202 -        get {                                                 
      203 -            withMainActorRefForRead { $0.pidProviders }       
      204 -        }                                                     
      205 -    }                                                         
      206 -                                                              
      207 -    private nonisolated var samplesUnsafe: [UUID: Sample] {   
      208 -        get { withMainActorRefForRead { $0.samples } }        
      209 -        set { withMainActorRefForWrite { $0.samples = newValue
          - } }                                                          
      210 -    }                                                         
      211 -                                                              
      212 -    private nonisolated var lastCpuTimesUnsafe: [pid_t: UInt64
          -] {                                                           
      213 -        get { withMainActorRefForRead { $0.lastCpuTimes } }   
      214 -        set { withMainActorRefForWrite { $0.lastCpuTimes = new
          -Value } }                                                     
      215 -    }                                                         
      216 -                                                              
      217 -    private nonisolated var lastSampleAtUnsafe: Date? {       
      218 -        get { withMainActorRefForRead { $0.lastSampleAt } }   
      219 -        set { withMainActorRefForWrite { $0.lastSampleAt = new
          -Value } }                                                     
      220 -    }                                                         
      221 -                                                              
      222 -    private nonisolated func withMainActorRefForRead<T>(_ body
          -: (SurfaceMetricsSampler) -> T) -> T {                        
      223 -        // Safe reads — the lock is held by the caller; we're 
          -just                                                          
      224 -        // dodging MainActor isolation for stored-property acc
          -ess.                                                          
      225 -        return body(Unmanaged.passUnretained(self).takeUnretai
          -nedValue())                                                   
      226 -    }                                                         
      227 -    private nonisolated func withMainActorRefForWrite(_ body: 
          -(SurfaceMetricsSampler) -> Void) {                            
      228 -        body(Unmanaged.passUnretained(self).takeUnretainedValu
          -e())                                                          
      229 -    }                                                         
      230 -                                                              
      231 -    private static func resolvePidSafely(_ provider: () -> pid
          -_t?) -> pid_t? {                                              
      232 -        // Provider closures are expected to be safe off-main 
          -— see                                                         
      233 -        // BrowserPanel where the closure reads `c11_webProces
          -sIdentifier`                                                  
      234 -        // (KVC against a WKWebView). If a future provider nee
          -ds main, it                                                   
      235 -        // can sync-hop internally.                           
      236 -        return provider()                                     
      237 -    }                                                         
      238 -                                                              
      186      // MARK: - proc_pid_rusage helpers
      187  
      188      /// Cumulative user+system CPU time in nanoseconds for `pi
           d`, via

⏺ Bash(xcrun swift-frontend -parse Sources/SurfaceMetricsSampler.swift 2>&1 |
      head -10; echo "exit=$?")
  ⎿  exit=0

  Searched for 1 pattern, read 1 file (ctrl+o to expand)

⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Added 9 lines
      2704              self.dispatchLifecycleTransition(from: from, to: 
            target)
      2705          }
      2706  
      2707 +        // C11-25 commit 6: register with the per-surface CPU
           +/RSS sampler.                                                
      2708 +        // The provider reads `_webProcessIdentifier` (KVC SP
           +I; safe to                                                   
      2709 +        // call off-main) at sample time so it always reflect
           +s the                                                        
      2710 +        // current WebContent process — including after proce
           +ss                                                           
      2711 +        // termination + auto-relaunch.                      
      2712 +        SurfaceMetricsSampler.shared.register(surfaceId: self
           +.id) { [weak self] in                                        
      2713 +            return self?.webView.c11_webProcessIdentifier    
      2714 +        }                                                    
      2715 +                                                             
      2716          // Navigate to initial URL if provided
      2717          if let url = initialURL {
      2718              shouldRenderWebView = true

⏺ Update(Sources/Panels/BrowserPanel.swift)
  ⎿  Added 1 line
      3280          webViewCancellables.removeAll()
      3281          faviconTask?.cancel()
      3282          faviconTask = nil
      3283 +        SurfaceMetricsSampler.shared.unregister(surfaceId: se
           +lf.id)                                                       
      3284      }
      3285  
      3286      // MARK: - Popup window management

⏺ Now register the terminal panel (provider returns nil for now):

⏺ Update(Sources/Panels/TerminalPanel.swift)
  ⎿  Added 8 lines
      110              surface?.setOcclusion(target == .active)
      111          }
      112  
      113 +        // C11-25 commit 6: register with the per-surface CPU/
          +RSS sampler.                                                  
      114 +        // Terminal child PID resolution is a follow-up (plan 
          +§2 row 5                                                      
      115 +        // notes the TTY → PID lookup needs a libghostty acces
          +sor or an                                                     
      116 +        // lsof-style helper). For now we register a nil-retur
          +ning                                                          
      117 +        // provider so the surface is known to the sampler; th
          +e sidebar                                                     
      118 +        // renders `—` for terminal CPU/RSS until the resolver
          + lands.                                                       
      119 +        SurfaceMetricsSampler.shared.register(surfaceId: surfa
          +ce.id) { nil }                                                
      120 +                                                              
      121          // Subscribe to surface's search state changes
      122          surface.$searchState
      123              .sink { [weak self] state in

⏺ Update(Sources/Panels/TerminalPanel.swift)  ⎿  Added 1 line
      232          unfocus()
      233          hostedView.setVisibleInUI(false)
      234          TerminalWindowPortalRegistry.detach(hostedView: hosted
           View)
      235 +        SurfaceMetricsSampler.shared.unregister(surfaceId: id)
      236  #if DEBUG
      237          dlog(
      238              "surface.panel.close.end panel=\(id.uuidString.pre
           fix(5)) " +

  Searched for 1 pattern, read 1 file (ctrl+o to expand)

⏺ Update(Sources/AppDelegate.swift)
  ⎿  Added 6 lines
      2358          // Register fenced code renderers for the markdown pa
            nel content pipeline.
      2359          FencedCodeRendererRegistry.shared.register(MermaidRen
            derer.shared)
      2360  
      2361 +        // C11-25: begin per-surface CPU/RSS sampling. Backgr
           +ound timer; the                                              
      2362 +        // sidebar reads samples via `SurfaceMetricsSampler.s
           +hared.sample(...)`                                           
      2363 +        // during body eval. Idempotent — safe across UI test
           +s that                                                       
      2364 +        // re-init the app delegate.                         
      2365 +        SurfaceMetricsSampler.shared.start()                 
      2366 +                                                             
      2367          // Start watching the user themes directory for hot-r
            eload.
      2368          ThemeManager.shared.startWatchingUserThemes()
      2369  

⏺ Now let me wire the sidebar to read sample and pass to TabItemView. Let me
  read the surrounding ContentView code first to know what's nearby and how it's
   structured.

  Searched for 1 pattern, read 1 file (ctrl+o to expand)

⏺ Update(Sources/ContentView.swift)
  ⎿  Added 5 lines
      8314  struct VerticalTabsSidebar: View {
      8315      @ObservedObject var updateViewModel: UpdateViewModel
      8316      @ObservedObject private var themeManager = ThemeManager.s
            hared
      8317 +    /// C11-25: subscribe to per-surface CPU/RSS sampler revi
           +sion bumps so                                                
      8318 +    /// the sidebar re-evaluates at the sample cadence (defau
           +lt 2 Hz).                                                    
      8319 +    /// `TabItemView.==` short-circuits body re-eval when the
           + row's                                                       
      8320 +    /// metrics value didn't change, so this stays cheap.    
      8321 +    @ObservedObject private var surfaceMetricsSampler = Surfa
           +ceMetricsSampler.shared                                      
      8322      let onSendFeedback: () -> Void
      8323      @EnvironmentObject var tabManager: TabManager
      8324      @EnvironmentObject var notificationStore: TerminalNotific
            ationStore

⏺ Update(Sources/ContentView.swift)
  ⎿  Added 9 lines
      8455                                          sources: sources
      8456                                      )
      8457                                  }()
      8458 +                                // C11-25: read the focused s
           +urface's most recent CPU/RSS                                 
      8459 +                                // sample as a precomputed `l
           +et`. The sampler's revision is                               
      8460 +                                // observed at the struct lev
           +el so this re-evaluates at the                               
      8461 +                                // sample cadence; equality o
           +n the resolved sample (rounded                               
      8462 +                                // for stability) decides whe
           +ther the row body re-renders.                                
      8463 +                                let surfaceMetricsSample: Sur
           +faceMetricsSampler.Sample? = {                               
      8464 +                                    guard let focusedId = tab
           +.focusedPanelId else { return nil }                          
      8465 +                                    return SurfaceMetricsSamp
           +ler.shared.sample(forSurfaceId: focusedId)                   
      8466 +                                }()                          
      8467                                  TabItemView(
      8468                                      tabManager: tabManager,
      8469                                      notificationStore: notifi
            cationStore,

⏺ Update(Sources/ContentView.swift)
  ⎿  Added 1 line
      8471                                      index: index,
      8472                                      isActive: isActive,
      8473                                      agentChip: agentChip,
      8474 +                                    surfaceMetricsSample: sur
           +faceMetricsSample,                                           
      8475                                      workspaceShortcutDigit: W
            orkspaceShortcutMapper.commandDigitForWorkspace(
      8476                                          at: index,
      8477                                          workspaceCount: works
            paceCount

⏺ Now update TabItemView to accept the new param and add to ==.

⏺ Update(Sources/ContentView.swift)
  ⎿  Added 20 lines
      10934          lhs.index == rhs.index &&
      10935          lhs.isActive == rhs.isActive &&
      10936          lhs.agentChip == rhs.agentChip &&
      10937 +        TabItemView.surfaceMetricsEqual(lhs.surfaceMetricsSa
            +mple, rhs.surfaceMetricsSample) &&                          
      10938          lhs.workspaceShortcutDigit == rhs.workspaceShortcutD
             igit &&
      10939          lhs.canCloseWorkspace == rhs.canCloseWorkspace &&
      10940          lhs.accessibilityWorkspaceCount == rhs.accessibility
             WorkspaceCount &&
     ...
      10950          lhs.sidebarFlashToken == rhs.sidebarFlashToken
      10951      }
      10952  
      10953 +    /// Equality on metric samples is rounded so sub-percent
            + / sub-MB                                                   
      10954 +    /// jitter at the 2 Hz sample cadence does not invalidat
            +e                                                           
      10955 +    /// `TabItemView.==` and force body re-eval. We only red
            +raw when the                                                
      10956 +    /// rendered text would change.                         
      10957 +    nonisolated static func surfaceMetricsEqual(            
      10958 +        _ a: SurfaceMetricsSampler.Sample?,                 
      10959 +        _ b: SurfaceMetricsSampler.Sample?                  
      10960 +    ) -> Bool {                                             
      10961 +        switch (a, b) {                                     
      10962 +        case (nil, nil):                                    
      10963 +            return true                                     
      10964 +        case let (a?, b?):                                  
      10965 +            return Int(a.cpuPct.rounded()) == Int(b.cpuPct.r
            +ounded())                                                   
      10966 +                && Int(a.rssMb.rounded()) == Int(b.rssMb.rou
            +nded())                                                     
      10967 +        default:                                            
      10968 +            return false                                    
      10969 +        }                                                   
      10970 +    }                                                       
      10971 +                                                            
      10972      // Use plain references instead of @EnvironmentObject to
              avoid subscribing
      10973      // to ALL changes on these objects. Body reads use preco
             mputed parameters;
      10974      // action handlers use the plain references without trig
             gering re-evaluation.

⏺ Update(Sources/ContentView.swift)
  ⎿  Added 4 lines
      10979      let index: Int
      10980      let isActive: Bool
      10981      let agentChip: AgentChip?
      10982 +    /// C11-25: most recent CPU/RSS sample for the workspace
            +'s focused                                                  
      10983 +    /// surface, or nil when no PID is registered (terminals
            + — pending                                                  
      10984 +    /// the TTY → child PID resolver follow-up).            
      10985 +    let surfaceMetricsSample: SurfaceMetricsSampler.Sample? 
      10986      let workspaceShortcutDigit: Int?
      10987      let canCloseWorkspace: Bool
      10988      let accessibilityWorkspaceCount: Int

⏺ Now render it in the body next to the agent chip.

⏺ Update(Sources/ContentView.swift)
  ⎿  Added 13 lines
      11358                          secondary: activeSecondaryColor(0.68
             )
      11359                      )
      11360                      Spacer(minLength: 0)
      11361 +                    // C11-25: per-surface CPU/RSS rendered 
            +next to the                                                 
      11362 +                    // agent chip when a sample is available
            +. Terminal                                                  
      11363 +                    // PID resolution is a follow-up; termin
            +als show no                                                 
      11364 +                    // metrics until that lands. Format keep
            +s the row                                                   
      11365 +                    // narrow: integer percent + integer MB 
            +or 1-decimal                                                
      11366 +                    // GB. Equality in `==` is rounded for s
            +tability.                                                   
      11367 +                    if let sample = surfaceMetricsSample {  
      11368 +                        Text(TabItemView.formatSurfaceMetric
            +s(sample))                                                  
      11369 +                            .font(.system(size: 9, design: .
            +monospaced))                                                
      11370 +                            .monospacedDigit()              
      11371 +                            .foregroundColor(activeSecondary
            +Color(0.55))                                                
      11372 +                            .accessibilityIdentifier("Sideba
            +rTabSurfaceMetrics")                                        
      11373 +                    }                                       
      11374                  }
      11375                  .padding(.top, 1)
      11376              }

⏺ Add the static formatter helper.

⏺ Update(Sources/ContentView.swift)
  ⎿  Added 14 lines
      10969          }
      10970      }
      10971  
      10972 +    /// Render a Sample as a compact "<cpu>% <mem>" string. 
      10973 +    /// CPU is integer percent (0%–800% on multi-core spikes
            +); memory is                                                
      10974 +    /// integer MB up to 1024, otherwise 1-decimal GB.      
      10975 +    nonisolated static func formatSurfaceMetrics(_ sample: S
            +urfaceMetricsSampler.Sample) -> String {                    
      10976 +        let cpu = "\(Int(sample.cpuPct.rounded()))%"        
      10977 +        let mem: String                                     
      10978 +        if sample.rssMb >= 1024 {                           
      10979 +            mem = String(format: "%.1fGB", sample.rssMb / 10
            +24)                                                         
      10980 +        } else {                                            
      10981 +            mem = "\(Int(sample.rssMb.rounded()))MB"        
      10982 +        }                                                   
      10983 +        return "\(cpu) \(mem)"                              
      10984 +    }                                                       
      10985 +                                                            
      10986      // Use plain references instead of @EnvironmentObject to
              avoid subscribing
      10987      // to ALL changes on these objects. Body reads use preco
             mputed parameters;
      10988      // action handlers use the plain references without trig
             gering re-evaluation.

⏺ Now register SurfaceMetricsSampler.swift in the Xcode project and verify
  syntax.

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      28      D7010BF0A1B2C3D4E5F60718 /* PaneMetadataStore.swift in Sour
          ces */ = {isa = PBXBuildFile; fileRef = D7010BF1A1B2C3D4E5F6071
          8 /* PaneMetadataStore.swift */; };
      29      D7C11250A1B2C3D4E5F60718 /* SurfaceLifecycle.swift in Sourc
          es */ = {isa = PBXBuildFile; fileRef = D7C11251A1B2C3D4E5F60718
           /* SurfaceLifecycle.swift */; };
      30      D7C11252A1B2C3D4E5F60718 /* BrowserSnapshotStore.swift in S
          ources */ = {isa = PBXBuildFile; fileRef = D7C11253A1B2C3D4E5F6
          0718 /* BrowserSnapshotStore.swift */; };
      31 +    D7C11254A1B2C3D4E5F60718 /* SurfaceMetricsSampler.swift in 
         +Sources */ = {isa = PBXBuildFile; fileRef = D7C11255A1B2C3D4E5F
         +60718 /* SurfaceMetricsSampler.swift */; };                    
      32      D8001BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift in Sou
          rces */ = {isa = PBXBuildFile; fileRef = D8001BF1A1B2C3D4E5F607
          18 /* WorkspaceApplyPlan.swift */; };
      33      D8002BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests.
          swift in Sources */ = {isa = PBXBuildFile; fileRef = D8002BF1A1
          B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests.swift */; };
      34      D8003BF0A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.swift i
          n Sources */ = {isa = PBXBuildFile; fileRef = D8003BF1A1B2C3D4E
          5F60718 /* WorkspaceLayoutExecutor.swift */; };

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      338      D7010BF1A1B2C3D4E5F60718 /* PaneMetadataStore.swift */ = {
           isa = PBXFileReference; lastKnownFileType = sourcecode.swift; 
           path = PaneMetadataStore.swift; sourceTree = "<group>"; };
      339      D7C11251A1B2C3D4E5F60718 /* SurfaceLifecycle.swift */ = {i
           sa = PBXFileReference; lastKnownFileType = sourcecode.swift; p
           ath = SurfaceLifecycle.swift; sourceTree = "<group>"; };
      340      D7C11253A1B2C3D4E5F60718 /* BrowserSnapshotStore.swift */ 
           = {isa = PBXFileReference; lastKnownFileType = sourcecode.swif
           t; path = BrowserSnapshotStore.swift; sourceTree = "<group>"; 
           };
      341 +    D7C11255A1B2C3D4E5F60718 /* SurfaceMetricsSampler.swift */
          + = {isa = PBXFileReference; lastKnownFileType = sourcecode.swi
          +ft; path = SurfaceMetricsSampler.swift; sourceTree = "<group>"
          +; };                                                          
      342      D8001BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift */ = 
           {isa = PBXFileReference; lastKnownFileType = sourcecode.swift;
            path = WorkspaceApplyPlan.swift; sourceTree = "<group>"; };
      343      D8002BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlanCodableTests
           .swift */ = {isa = PBXFileReference; lastKnownFileType = sourc
           ecode.swift; path = WorkspaceApplyPlanCodableTests.swift; sour
           ceTree = "<group>"; };
      344      D8003BF1A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.swift 
           */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.s
           wift; path = WorkspaceLayoutExecutor.swift; sourceTree = "<gro
           up>"; };

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      709          D7010BF1A1B2C3D4E5F60718 /* PaneMetadataStore.swift */
           ,
      710          D7C11251A1B2C3D4E5F60718 /* SurfaceLifecycle.swift */,
      711          D7C11253A1B2C3D4E5F60718 /* BrowserSnapshotStore.swift
            */,
      712 +        D7C11255A1B2C3D4E5F60718 /* SurfaceMetricsSampler.swif
          +t */,                                                         
      713          D8001BF1A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift *
           /,
      714          D8003BF1A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.sw
           ift */,
      715          D8005BF1A1B2C3D4E5F60718 /* WorkspaceSnapshot.swift */
           ,

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      1126          D7010BF0A1B2C3D4E5F60718 /* PaneMetadataStore.swift i
            n Sources */,
      1127          D7C11250A1B2C3D4E5F60718 /* SurfaceLifecycle.swift in
             Sources */,
      1128          D7C11252A1B2C3D4E5F60718 /* BrowserSnapshotStore.swif
            t in Sources */,
      1129 +        D7C11254A1B2C3D4E5F60718 /* SurfaceMetricsSampler.swi
           +ft in Sources */,                                            
      1130          D8001BF0A1B2C3D4E5F60718 /* WorkspaceApplyPlan.swift 
            in Sources */,
      1131          D8003BF0A1B2C3D4E5F60718 /* WorkspaceLayoutExecutor.s
            wift in Sources */,
      1132          D8005BF0A1B2C3D4E5F60718 /* WorkspaceSnapshot.swift i
            n Sources */,

⏺ Bash(xcrun swift-frontend -parse Sources/SurfaceMetricsSampler.swift
      Sources/Panels/BrowserPanel.swift Sources/Panels/TerminalPanel.swift
      Sources/AppDelegate.swift S…)
  ⎿  exit=0

⏺ Bash(git add Sources/SurfaceMetricsSampler.swift
      Sources/Panels/BrowserPanel.swift Sources/Panels/TerminalPanel.swift
      Sources/AppDelegate.swift Sources/ContentView.s…)
  ⎿   GhosttyTabs.xcodeproj/project.pbxproj |   4 +
      Sources/AppDelegate.swift             |   6 +
      Sources/ContentView.swift             |  66 +++++++++++
     … +5 lines (ctrl+o to expand)
⏺ Bash(git commit -m "$(cat <<'EOF'
      C11-25 commit 6/9: SurfaceMetricsSampler + sidebar CPU/MEM render…)
  ⎿  [c11-25-surface-lifecycle 7bffed86] C11-25 commit 6/9: SurfaceMetricsS
     ampler + sidebar CPU/MEM render
      6 files changed, 309 insertions(+)
     … +4 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 6/9 landed: SurfaceMetricsSampler (browser CPU/RSS via
      _webProcessIdentifier SPI) + s…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

  Searched for 2 patterns, read 1 file (ctrl+o to expand)

⏺ Update(Sources/Workspace.swift)
  ⎿  Added 8 lines
      5106      /// row pulse together. Visual-only; never affects select
            ion.
      5107      @Published private(set) var sidebarFlashToken: Int = 0
      5108  
      5109 +    /// C11-25: workspace-level operator hibernate flag. True
           + when the                                                    
      5110 +    /// operator has explicitly hibernated this workspace via
           + the                                                         
      5111 +    /// "Hibernate Workspace" context menu (or socket equival
           +ent). Survives                                               
      5112 +    /// `c11 snapshot` / `restore` via the canonical `lifecyc
           +le_state`                                                    
      5113 +    /// metadata mirror on each panel — the workspace flag is
           + rebuilt on                                                  
      5114 +    /// restore from "any panel hibernated".                 
      5115 +    @Published var isHibernated: Bool = false                
      5116 +                                                             
      5117      /// Subscriptions for panel updates (e.g., browser title 
            changes)
      5118      private var panelSubscriptions: [UUID: AnyCancellable] = 
            [:]
      5119  

⏺ Now add hibernate/resume methods. Let me add them near other workspace-level
  operations.

⏺ Update(Sources/Workspace.swift)
  ⎿  Added 26 lines
      5981          panels[panelId] as? BrowserPanel
      5982      }
      5983  
      5984 +    /// C11-25: hibernate every browser panel in the workspac
           +e and flip                                                   
      5985 +    /// the workspace-level flag. Terminals stay on the auto-
           +throttle                                                     
      5986 +    /// path (workspace deselect already pauses libghostty re
           +ndering;                                                     
      5987 +    /// SIGSTOP for terminals is deferred). Markdown surfaces
           + are                                                         
      5988 +    /// unaffected. Idempotent.                              
      5989 +    func hibernate() {                                       
      5990 +        for panel in panels.values {                         
      5991 +            if let browser = panel as? BrowserPanel {        
      5992 +                browser.setHibernated(true)                  
      5993 +            }                                                
      5994 +        }                                                    
      5995 +        isHibernated = true                                  
      5996 +    }                                                        
      5997 +                                                             
      5998 +    /// C11-25: resume the workspace. Browser panels transiti
           +on out of                                                    
      5999 +    /// `.hibernated` (back to `.active`); the auto-throttle 
           +path takes                                                   
      6000 +    /// it from there based on visibility. Idempotent.       
      6001 +    func resume() {                                          
      6002 +        for panel in panels.values {                         
      6003 +            if let browser = panel as? BrowserPanel {        
      6004 +                browser.setHibernated(false)                 
      6005 +            }                                                
      6006 +        }                                                    
      6007 +        isHibernated = false                                 
      6008 +    }                                                        
      6009 +                                                             
      6010      func markdownPanel(for panelId: UUID) -> MarkdownPanel? {
      6011          panels[panelId] as? MarkdownPanel
      6012      }

⏺ Now the menu items in c11App.swift.

⏺ Update(Sources/c11App.swift)
  ⎿  File must be read first

  Read 1 file (ctrl+o to expand)

⏺ Update(Sources/c11App.swift)
  ⎿  Added 19 lines
      1391  
      1392          Divider()
      1393  
      1394 +        // C11-25: hibernate / resume the workspace. Browser 
           +surfaces                                                     
      1395 +        // capture a snapshot, terminate their WebContent pro
           +cesses, and                                                  
      1396 +        // render a placeholder until resume; terminals stay 
           +on the auto                                                  
      1397 +        // throttle path. The menu flips between Hibernate an
           +d Resume                                                     
      1398 +        // based on `workspace.isHibernated`.                
      1399 +        if workspace?.isHibernated == true {                 
      1400 +            Button(String(localized: "contextMenu.resumeWorks
           +pace", defaultValue: "Resume Workspace")) {                  
      1401 +                workspace?.resume()                          
      1402 +            }                                                
      1403 +            .disabled(workspace == nil)                      
      1404 +        } else {                                             
      1405 +            Button(String(localized: "contextMenu.hibernateWo
           +rkspace", defaultValue: "Hibernate Workspace")) {            
      1406 +                workspace?.hibernate()                       
      1407 +            }                                                
      1408 +            .disabled(workspace == nil)                      
      1409 +        }                                                    
      1410 +                                                             
      1411 +        Divider()                                            
      1412 +                                                             
      1413          Button(String(localized: "contextMenu.markWorkspaceRe
            ad", defaultValue: "Mark Workspace as Read")) {
      1414              markSelectedWorkspaceRead(in: manager)
      1415          }

  Searched for 3 patterns, read 1 file (ctrl+o to expand)

⏺ Update(Resources/Localizable.xcstrings)
  ⎿  Added 11 lines
      18893          }
      18894        }
      18895      },
      18896 +    "contextMenu.hibernateWorkspace": {                     
      18897 +      "extractionState": "manual",                          
      18898 +      "localizations": {                                    
      18899 +        "en": {                                             
      18900 +          "stringUnit": {                                   
      18901 +            "state": "translated",                          
      18902 +            "value": "Hibernate Workspace"                  
      18903 +          }                                                 
      18904 +        }                                                   
      18905 +      }                                                     
      18906 +    },                                                      
      18907      "contextMenu.markWorkspaceRead": {
      18908        "extractionState": "manual",
      18909        "localizations": {

  Searched for 1 pattern, read 1 file (ctrl+o to expand)

⏺ Update(Resources/Localizable.xcstrings)
  ⎿  Added 11 lines
      19656          }
      19657        }
      19658      },
      19659 +    "contextMenu.resumeWorkspace": {                        
      19660 +      "extractionState": "manual",                          
      19661 +      "localizations": {                                    
      19662 +        "en": {                                             
      19663 +          "stringUnit": {                                   
      19664 +            "state": "translated",                          
      19665 +            "value": "Resume Workspace"                     
      19666 +          }                                                 
      19667 +        }                                                   
      19668 +      }                                                     
      19669 +    },                                                      
      19670      "contextMenu.unpinWorkspace": {
      19671        "extractionState": "manual",
      19672        "localizations": {

⏺ Bash(python3 -c "import json;
      json.load(open('Resources/Localizable.xcstrings'))" 2>&1 | head -3; echo
      "json_exit=$?"; xcrun swift-frontend -parse Sources/c11App.swi…)
  ⎿  json_exit=0
     swift_exit=0

⏺ Bash(git add Sources/c11App.swift Sources/Workspace.swift
      Resources/Localizable.xcstrings && git diff --cached --stat && git commit
      -m "$(cat <<'EOF'
      C11-25 commit 7…)
  ⎿   Resources/Localizable.xcstrings | 22 ++++++++++++++++++++++
      Sources/Workspace.swift         | 34 ++++++++++++++++++++++++++++++++
     ++
     … +8 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 7/9 landed: Hibernate/Resume Workspace context menu + 2 English
      i18n keys (DoD #6, tr…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle
  Searched for 2 patterns, read 1 file (ctrl+o to expand)

⏺ Update(Sources/Workspace.swift)
  ⎿  Added 40 lines
      5981          panels[panelId] as? BrowserPanel
      5982      }
      5983  
      5984 +    /// C11-25 commit 8: rehydrate workspace + panel lifecycl
           +e state from                                                 
      5985 +    /// `lifecycle_state` canonical metadata after a `c11 res
           +tore` /                                                      
      5986 +    /// blueprint apply. Called by `WorkspaceLayoutExecutor` 
           +once all                                                     
      5987 +    /// surfaces and metadata are materialized.              
      5988 +    ///                                                      
      5989 +    /// For browser panels with `lifecycle_state == "hibernat
           +ed"`:                                                        
      5990 +    ///   `setHibernated(true)` re-triggers the snapshot+term
           +inate path                                                   
      5991 +    ///   so the restored panel ends up in the same operator-
           +pinned                                                       
      5992 +    ///   state. Snapshots are in-memory only in C11-25, so t
           +he                                                           
      5993 +    ///   placeholder will render a neutral background until 
           +the                                                          
      5994 +    ///   operator resumes — operator accepted in §0a.       
      5995 +    ///                                                      
      5996 +    /// For terminals/markdown the canonical metadata is pres
           +erved but                                                    
      5997 +    /// no runtime change is dispatched (auto-throttle handle
           +s                                                            
      5998 +    /// visibility; explicit terminal hibernate is deferred).
      5999 +    ///                                                      
      6000 +    /// `isHibernated` is rebuilt from "any browser panel hib
           +ernated".                                                    
      6001 +    func restoreLifecycleStateFromMetadata() {               
      6002 +        var anyHibernated = false                            
      6003 +        for (panelId, panel) in panels {                     
      6004 +            let snapshot = SurfaceMetadataStore.shared.getMet
           +adata(                                                       
      6005 +                workspaceId: id,                             
      6006 +                surfaceId: panelId                           
      6007 +            )                                                
      6008 +            guard let stateStr = snapshot.metadata[MetadataKe
           +y.lifecycleState] as? String,                                
      6009 +                  let state = SurfaceLifecycleState(rawValue:
           + stateStr) else {                                            
      6010 +                continue                                     
      6011 +            }                                                
      6012 +            if state == .hibernated {                        
      6013 +                anyHibernated = true                         
      6014 +                if let browser = panel as? BrowserPanel {    
      6015 +                    browser.setHibernated(true)              
      6016 +                }                                            
      6017 +            }                                                
      6018 +        }                                                    
      6019 +        if isHibernated != anyHibernated {                   
      6020 +            isHibernated = anyHibernated                     
      6021 +        }                                                    
      6022 +    }                                                        
      6023 +                                                             
      6024      /// C11-25: hibernate every browser panel in the workspac
            e and flip
      6025      /// the workspace-level flag. Terminals stay on the auto-
            throttle
      6026      /// path (workspace deselect already pauses libghostty re
            ndering;

⏺ Now hook it from WorkspaceLayoutExecutor.

⏺ Update(Sources/WorkspaceLayoutExecutor.swift)
  ⎿  Added 9 lines
      266              ))
      267          }
      268  
      269 +        // C11-25 commit 8 — rehydrate per-panel + workspace-l
          +evel                                                          
      270 +        // lifecycle from the canonical `lifecycle_state` meta
          +data that                                                     
      271 +        // has been applied above. For hibernated browsers thi
          +s fires                                                       
      272 +        // the snapshot+terminate path so the restored workspa
          +ce                                                            
      273 +        // matches the pre-snapshot operator intent. Cheap-tie
          +r                                                             
      274 +        // throttled state is implicit from workspace-selectio
          +n and                                                         
      275 +        // does not need rehydration here.                    
      276 +        workspace.restoreLifecycleStateFromMetadata()         
      277 +                                                              
      278          // Step 8 — assemble refs. The executor mints refs for
            every surface
      279          // and pane that was successfully created; plan-local 
           surface ids map
      280          // 1:1 to live `surface:N` / `pane:N` refs via the inj
           ected minters.

⏺ Bash(xcrun swift-frontend -parse Sources/Workspace.swift
      Sources/WorkspaceLayoutExecutor.swift 2>&1 | head -10; echo "exit=$?")
  ⎿  exit=0

⏺ Bash(git add Sources/Workspace.swift Sources/WorkspaceLayoutExecutor.swift &&
      git diff --cached --stat && git commit -m "$(cat <<'EOF'
      C11-25 commit 8/9: rehydrate l…)
  ⎿   Sources/Workspace.swift               | 40 ++++++++++++++++++++++++++
     +++++++++
      Sources/WorkspaceLayoutExecutor.swift |  9 ++++++++
     … +7 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 8/9 landed: rehydrate per-panel + workspace-level lifecycle from
      canonical metadata o…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

  Read 1 file, listed 1 directory (ctrl+o to expand)

⏺ Write(c11Tests/SurfaceLifecycleTests.swift)
  ⎿  Wrote 248 lines to c11Tests/SurfaceLifecycleTests.swift
       2 import XCTest
       3 #if canImport(c11_DEV)
       4 @testable import c11_DEV
       5 #elseif canImport(c11)
       6 @testable import c11
       8 #endif
       9 /// Unit tests for the C11-25 lifecycle primitive — the transiti
         on
      10 /// validator on `SurfaceLifecycleState`, the canonical metadata
          mirror
     … +274 lines (ctrl+o to expand)

⏺ Now register the test file in the project. Then write the Python socket test.

  Searched for 1 pattern (ctrl+o to expand)

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      50      D800CBF0A1B2C3D4E5F60718 /* WorkspaceSnapshotCaptureTests.s
          wift in Sources */ = {isa = PBXBuildFile; fileRef = D800CBF1A1B
          2C3D4E5F60718 /* WorkspaceSnapshotCaptureTests.swift */; };
      51      D800DBF0A1B2C3D4E5F60718 /* WorkspaceSnapshotRoundTripAccep
          tanceTests.swift in Sources */ = {isa = PBXBuildFile; fileRef =
           D800DBF1A1B2C3D4E5F60718 /* WorkspaceSnapshotRoundTripAcceptan
          ceTests.swift */; };
      52      D800EBF0A1B2C3D4E5F60718 /* SurfaceMetadataStoreValidationT
          ests.swift in Sources */ = {isa = PBXBuildFile; fileRef = D800E
          BF1A1B2C3D4E5F60718 /* SurfaceMetadataStoreValidationTests.swif
          t */; };
      53 +    D7C11260A1B2C3D4E5F60718 /* SurfaceLifecycleTests.swift in 
         +Sources */ = {isa = PBXBuildFile; fileRef = D7C11261A1B2C3D4E5F
         +60718 /* SurfaceLifecycleTests.swift */; };                    
      54      D800FBF0A1B2C3D4E5F60718 /* WorkspaceSnapshotStoreSecurityT
          ests.swift in Sources */ = {isa = PBXBuildFile; fileRef = D800F
          BF1A1B2C3D4E5F60718 /* WorkspaceSnapshotStoreSecurityTests.swif
          t */; };
      55      D8010BF0A1B2C3D4E5F60718 /* WorkspacePlanCapture.swift in S
          ources */ = {isa = PBXBuildFile; fileRef = D8010BF1A1B2C3D4E5F6
          0718 /* WorkspacePlanCapture.swift */; };
      56      D8011BF0A1B2C3D4E5F60718 /* WorkspaceBlueprintFile.swift in
           Sources */ = {isa = PBXBuildFile; fileRef = D8011BF1A1B2C3D4E5
          F60718 /* WorkspaceBlueprintFile.swift */; };

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      361      D800CBF1A1B2C3D4E5F60718 /* WorkspaceSnapshotCaptureTests.
           swift */ = {isa = PBXFileReference; lastKnownFileType = source
           code.swift; path = WorkspaceSnapshotCaptureTests.swift; source
           Tree = "<group>"; };
      362      D800DBF1A1B2C3D4E5F60718 /* WorkspaceSnapshotRoundTripAcce
           ptanceTests.swift */ = {isa = PBXFileReference; lastKnownFileT
           ype = sourcecode.swift; path = WorkspaceSnapshotRoundTripAccep
           tanceTests.swift; sourceTree = "<group>"; };
      363      D800EBF1A1B2C3D4E5F60718 /* SurfaceMetadataStoreValidation
           Tests.swift */ = {isa = PBXFileReference; lastKnownFileType = 
           sourcecode.swift; path = SurfaceMetadataStoreValidationTests.s
           wift; sourceTree = "<group>"; };
      364 +    D7C11261A1B2C3D4E5F60718 /* SurfaceLifecycleTests.swift */
          + = {isa = PBXFileReference; lastKnownFileType = sourcecode.swi
          +ft; path = SurfaceLifecycleTests.swift; sourceTree = "<group>"
          +; };                                                          
      365      D800FBF1A1B2C3D4E5F60718 /* WorkspaceSnapshotStoreSecurity
           Tests.swift */ = {isa = PBXFileReference; lastKnownFileType = 
           sourcecode.swift; path = WorkspaceSnapshotStoreSecurityTests.s
           wift; sourceTree = "<group>"; };
      366      D8010BF1A1B2C3D4E5F60718 /* WorkspacePlanCapture.swift */ 
           = {isa = PBXFileReference; lastKnownFileType = sourcecode.swif
           t; path = WorkspacePlanCapture.swift; sourceTree = "<group>"; 
           };
      367      D8011BF1A1B2C3D4E5F60718 /* WorkspaceBlueprintFile.swift *
           / = {isa = PBXFileReference; lastKnownFileType = sourcecode.sw
           ift; path = WorkspaceBlueprintFile.swift; sourceTree = "<group
           >"; };

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      944            D800CBF1A1B2C3D4E5F60718 /* WorkspaceSnapshotCapture
           Tests.swift */,
      945            D800DBF1A1B2C3D4E5F60718 /* WorkspaceSnapshotRoundTr
           ipAcceptanceTests.swift */,
      946            D800EBF1A1B2C3D4E5F60718 /* SurfaceMetadataStoreVali
           dationTests.swift */,
      947 +          D7C11261A1B2C3D4E5F60718 /* SurfaceLifecycleTests.sw
          +ift */,                                                       
      948            D800FBF1A1B2C3D4E5F60718 /* WorkspaceSnapshotStoreSe
           curityTests.swift */,
      949          D8014BF1A1B2C3D4E5F60718 /* WorkspaceBlueprintFileCoda
           bleTests.swift */,
      950          D8015BF1A1B2C3D4E5F60718 /* WorkspaceBlueprintStoreTes
           ts.swift */,

⏺ Update(GhosttyTabs.xcodeproj/project.pbxproj)
  ⎿  Added 1 line
      1333            D800CBF0A1B2C3D4E5F60718 /* WorkspaceSnapshotCaptur
            eTests.swift in Sources */,
      1334            D800DBF0A1B2C3D4E5F60718 /* WorkspaceSnapshotRoundT
            ripAcceptanceTests.swift in Sources */,
      1335            D800EBF0A1B2C3D4E5F60718 /* SurfaceMetadataStoreVal
            idationTests.swift in Sources */,
      1336 +          D7C11260A1B2C3D4E5F60718 /* SurfaceLifecycleTests.s
           +wift in Sources */,                                          
      1337            D800FBF0A1B2C3D4E5F60718 /* WorkspaceSnapshotStoreS
            ecurityTests.swift in Sources */,
      1338            D8014BF0A1B2C3D4E5F60718 /* WorkspaceBlueprintFileC
            odableTests.swift in Sources */,
      1339            D8015BF0A1B2C3D4E5F60718 /* WorkspaceBlueprintStore
            Tests.swift in Sources */,

  Searched for 1 pattern, read 2 files, listed 1 directory (ctrl+o to expand)

⏺ Write(tests_v2/test_surface_lifecycle.py)
  ⎿  Wrote 150 lines to tests_v2/test_surface_lifecycle.py
       2 """C11-25 surface lifecycle smoke test.
       3 
       4 Validates that the canonical `lifecycle_state` metadata key is w
         ired
       5 through the surface.set_metadata / surface.get_metadata socket p
       6 ath:
       7   - Accepted values: active, throttled, suspended, hibernated.
       8   - Rejected values: anything else, including any non-string.
       9   - Round-trips through the metadata store and is readable via
      10     surface.get_metadata.
     … +154 lines (ctrl+o to expand)

⏺ Bash(python3 -c "import ast;
      ast.parse(open('tests_v2/test_surface_lifecycle.py').read())" && echo
      "py_ok=0"; xcrun swift-frontend -parse c11Tests/SurfaceLifecycleTe…)
  ⎿  py_ok=0
     swift_exit=0

  Searched for 4 patterns, read 1 file (ctrl+o to expand)
⏺ Bash(git add c11Tests/SurfaceLifecycleTests.swift
      tests_v2/test_surface_lifecycle.py GhosttyTabs.xcodeproj/project.pbxproj
      && git diff --cached --stat && git commit…)
  ⎿   GhosttyTabs.xcodeproj/project.pbxproj |   4 +
      c11Tests/SurfaceLifecycleTests.swift  | 248 +++++++++++++++++++++++++
     +++++++++
     … +10 lines (ctrl+o to expand)

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25
      "Commit 9/9 landed: SurfaceLifecycleTests.swift (transition validator,
      canonical metadata, co…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

⏺ All 9 commits landed. Let me gather the diff stats for the completion comment.

⏺ Bash(echo "=== commit list ==="; git log --oneline origin/main..HEAD; echo "";
       echo "=== files changed total ==="; git diff --stat origin/main...HEAD |
      tail -1; echo…)
  ⎿  === commit list ===
     8354b7fe C11-25 commit 9/9: lifecycle tests (Swift unit + Python socke
     t smoke)
     … +25 lines (ctrl+o to expand)

⏺ Now I'll bump status to review and write the completion comment.

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice comment C11-25 "$(cat
       <<'EOF'
      **C11-25 Impl complete. All 9 commits pushed. Status → review.**…)
  ⎿  Comment added to task_01KQTQ05R0G4CSMJRQPK7XVKY3
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

⏺ Bash(cd /Users/atin/Projects/Stage11/code/c11 && lattice status C11-25 review
      --actor "agent:claude-opus-4-7-c11-25-impl" 2>&1 | tail -3)
  ⎿  Status: in_progress -> review (C11-25)
       Next: run 'lattice code-review C11-25' (review_mode: inline) before
     moving to done.
  ⎿  Shell cwd was reset to /Users/atin/Projects/Stage11/code/c11-worktrees
     /c11-25-surface-lifecycle

⏺ Bash(c11 set-metadata --surface 6AEB53B0-D165-43A8-A683-BEC48FB73782 --key
      status --value "review-handoff")
  ⎿  OK surface:41
       status: applied

⏺ Impl phase complete. C11-25 status is now review.

  Summary: 9 commits landed and pushed to c11-25-surface-lifecycle
  (14a43a7e..8354b7fe), +1473 LoC across 17 files. All five operator-approved
  behaviors shipped:

  - Lifecycle primitive (active/throttled/suspended/hibernated) with canonical
  lifecycle_state metadata mirror
  - Terminal occlusion via libghostty (DoD #3 path)
  - Browser cheap-tier detach via existing shouldAttachWebView gate,
  lifecycle-observed (DoD #1 path)
  - ARC-grade hibernate — WKWebView.takeSnapshot + WebContent teardown via
  _webProcessIdentifier SPI (DoD #2 path)
  - Per-surface CPU/RSS sampler + sidebar render (DoD #5 path, browser-only —
  terminal PID resolver is documented follow-up)
  - Hibernate/Resume Workspace context menu + 2 English-only i18n keys (DoD #6
  path)

  Snapshot/restore wires through automatically: rehydration runs after the
  executor's per-surface metadata writes.

  Deviations + adjacent observations are spelled out in the lattice completion
  comment for the Review phase. Translator pass is needed for the 2 new strings
  (delegator's call); 30 fps cap remains in C11-25c per the operator decision in
   §0a. Stopping per the prompt's stop-boundary instruction.

✻ Worked for 48m 4s

※ recap: Goal: ship C11-25 surface lifecycle perf (webview suspension, terminal throttle, sidebar CPU/MEM, Hibernate Workspace). All 9 impl commits are pushed and Lattice status is on review. Next: hand off to the Review sub-agent. (disable recaps in /config)