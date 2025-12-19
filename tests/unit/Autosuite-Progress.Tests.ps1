<#
.SYNOPSIS
    Pester tests for progress UI module.

.DESCRIPTION
    Tests for provisioning/engine/progress.ps1 progress tracking functionality.
    Validates state management, event queue, and rendering functions.
#>

BeforeAll {
    $ErrorActionPreference = 'Stop'
    
    # Import progress module
    $progressModulePath = Join-Path $PSScriptRoot "..\..\provisioning\engine\progress.ps1"
    . $progressModulePath
}

Describe "Progress Event Queue" {
    It "Creates a new event queue" {
        $queue = New-ProgressEventQueue
        
        $queue | Should -Not -BeNullOrEmpty
        $queue.GetType().Name | Should -Be 'Hashtable'
        
        # Verify queue works by adding and retrieving an event
        Add-ProgressEvent -EventQueue $queue -EventType 'AppStarted' -Data @{ AppId = 'test' }
        $events = Get-ProgressEvents -EventQueue $queue
        $events.Count | Should -Be 1
    }
    
    It "Adds events to the queue" {
        $queue = New-ProgressEventQueue
        
        Add-ProgressEvent -EventQueue $queue -EventType 'AppStarted' -Data @{ AppId = 'test-app' }
        
        $events = Get-ProgressEvents -EventQueue $queue
        $events.Count | Should -Be 1
        $events[0].Type | Should -Be 'AppStarted'
        $events[0].Data.AppId | Should -Be 'test-app'
    }
    
    It "Dequeues multiple events in order" {
        $queue = New-ProgressEventQueue
        
        Add-ProgressEvent -EventQueue $queue -EventType 'AppStarted' -Data @{ AppId = 'app1' }
        Add-ProgressEvent -EventQueue $queue -EventType 'AppStarted' -Data @{ AppId = 'app2' }
        Add-ProgressEvent -EventQueue $queue -EventType 'AppCompleted' -Data @{ AppId = 'app1'; Success = $true }
        
        $events = Get-ProgressEvents -EventQueue $queue
        $events.Count | Should -Be 3
        $events[0].Data.AppId | Should -Be 'app1'
        $events[1].Data.AppId | Should -Be 'app2'
        $events[2].Data.AppId | Should -Be 'app1'
        $events[2].Type | Should -Be 'AppCompleted'
    }
    
    It "Returns empty array when queue is empty" {
        $queue = New-ProgressEventQueue
        
        $events = Get-ProgressEvents -EventQueue $queue
        $events | Should -BeNullOrEmpty
    }
}

Describe "Progress State Management" {
    It "Creates a new progress state with correct defaults" {
        $state = New-ProgressState -TotalApps 10 -ParallelThrottle 3
        
        $state.TotalApps | Should -Be 10
        $state.CompletedCount | Should -Be 0
        $state.FailedCount | Should -Be 0
        $state.ParallelThrottle | Should -Be 3
        $state.RunningApps | Should -BeNullOrEmpty
        $state.QueuedCount | Should -Be 0
    }
    
    It "Creates sequential mode state (throttle 0)" {
        $state = New-ProgressState -TotalApps 5 -ParallelThrottle 0
        
        $state.TotalApps | Should -Be 5
        $state.ParallelThrottle | Should -Be 0
    }
    
    It "Updates state on AppStarted event" {
        $state = New-ProgressState -TotalApps 5 -ParallelThrottle 3
        $progressEvent = @{
            Type = 'AppStarted'
            Data = @{ AppId = 'test-app' }
        }
        
        Update-ProgressState -State $state -Event $progressEvent
        
        $state.RunningApps | Should -Contain 'test-app'
        $state.RunningApps.Count | Should -Be 1
    }
    
    It "Updates state on AppCompleted event (success)" {
        $state = New-ProgressState -TotalApps 5 -ParallelThrottle 3
        $state.RunningApps = @('test-app')
        
        $progressEvent = @{
            Type = 'AppCompleted'
            Data = @{ AppId = 'test-app'; Success = $true }
        }
        
        Update-ProgressState -State $state -Event $progressEvent
        
        $state.RunningApps | Should -Not -Contain 'test-app'
        $state.CompletedCount | Should -Be 1
        $state.FailedCount | Should -Be 0
    }
    
    It "Updates state on AppCompleted event (failure)" {
        $state = New-ProgressState -TotalApps 5 -ParallelThrottle 3
        $state.RunningApps = @('test-app')
        
        $progressEvent = @{
            Type = 'AppCompleted'
            Data = @{ AppId = 'test-app'; Success = $false }
        }
        
        Update-ProgressState -State $state -Event $progressEvent
        
        $state.RunningApps | Should -Not -Contain 'test-app'
        $state.CompletedCount | Should -Be 1
        $state.FailedCount | Should -Be 1
    }
    
    It "Handles multiple running apps" {
        $state = New-ProgressState -TotalApps 10 -ParallelThrottle 3
        
        $event1 = @{ Type = 'AppStarted'; Data = @{ AppId = 'app1' } }
        $event2 = @{ Type = 'AppStarted'; Data = @{ AppId = 'app2' } }
        $event3 = @{ Type = 'AppStarted'; Data = @{ AppId = 'app3' } }
        
        Update-ProgressState -State $state -Event $event1
        Update-ProgressState -State $state -Event $event2
        Update-ProgressState -State $state -Event $event3
        
        $state.RunningApps.Count | Should -Be 3
        $state.RunningApps | Should -Contain 'app1'
        $state.RunningApps | Should -Contain 'app2'
        $state.RunningApps | Should -Contain 'app3'
    }
}

Describe "Progress Bar Rendering" {
    It "Generates progress bar with correct width" {
        $bar = Get-ProgressBar -Completed 5 -Total 10 -Width 20
        
        $bar | Should -Match '^\[.*\]$'
        $bar.Length | Should -Be 22  # 20 chars + 2 brackets
    }
    
    It "Shows 50% progress correctly" {
        $bar = Get-ProgressBar -Completed 5 -Total 10 -Width 10
        
        # Should have 5 filled and 5 empty
        $bar | Should -Match '^\[█{5}░{5}\]$'
    }
    
    It "Shows 0% progress" {
        $bar = Get-ProgressBar -Completed 0 -Total 10 -Width 10
        
        $bar | Should -Match '^\[░{10}\]$'
    }
    
    It "Shows 100% progress" {
        $bar = Get-ProgressBar -Completed 10 -Total 10 -Width 10
        
        $bar | Should -Match '^\[█{10}\]$'
    }
    
    It "Handles zero total gracefully" {
        $bar = Get-ProgressBar -Completed 0 -Total 0 -Width 10
        
        $bar | Should -Match '^\[░{10}\]$'
    }
}

Describe "Progress Line Formatting" {
    It "Formats progress line for sequential mode" {
        $state = New-ProgressState -TotalApps 56 -ParallelThrottle 0
        $state.CompletedCount = 18
        
        $line = Format-ProgressLine -State $state
        
        $line | Should -Match '18 / 56 apps'
        $line | Should -Not -Match 'parallel'
    }
    
    It "Formats progress line for parallel mode" {
        $state = New-ProgressState -TotalApps 56 -ParallelThrottle 3
        $state.CompletedCount = 18
        $state.RunningApps = @('app1', 'app2', 'app3')
        $state.QueuedCount = 35
        
        $line = Format-ProgressLine -State $state
        
        $line | Should -Match '18 / 56 apps'
        $line | Should -Match 'parallel: 3'
        $line | Should -Match 'queued: 35'
    }
    
    It "Shows correct running count in parallel mode" {
        $state = New-ProgressState -TotalApps 10 -ParallelThrottle 3
        $state.RunningApps = @('app1', 'app2')
        
        $line = Format-ProgressLine -State $state
        
        $line | Should -Match 'parallel: 2'
    }
}

Describe "Running Apps Formatting" {
    It "Returns empty string when no apps running" {
        $state = New-ProgressState -TotalApps 10 -ParallelThrottle 3
        
        $line = Format-RunningApps -State $state
        
        $line | Should -BeNullOrEmpty
    }
    
    It "Formats single running app" {
        $state = New-ProgressState -TotalApps 10 -ParallelThrottle 0
        $state.RunningApps = @('test-app')
        
        $line = Format-RunningApps -State $state
        
        $line | Should -Match 'Running \(1\): test-app'
    }
    
    It "Formats multiple running apps" {
        $state = New-ProgressState -TotalApps 10 -ParallelThrottle 3
        $state.RunningApps = @('app1', 'app2', 'app3')
        
        $line = Format-RunningApps -State $state
        
        $line | Should -Match 'Running \(3\):'
        $line | Should -Match 'app1'
        $line | Should -Match 'app2'
        $line | Should -Match 'app3'
    }
    
    It "Truncates long app lists" {
        $state = New-ProgressState -TotalApps 100 -ParallelThrottle 10
        $longAppList = 1..20 | ForEach-Object { "very-long-app-name-$_" }
        $state.RunningApps = $longAppList
        
        $line = Format-RunningApps -State $state
        
        $line.Length | Should -BeLessOrEqual 120
        $line | Should -Match '\.\.\.$'
    }
}

Describe "Progress State Transitions" {
    It "Correctly tracks sequential app lifecycle" {
        $state = New-ProgressState -TotalApps 3 -ParallelThrottle 0
        
        # App 1 starts
        Update-ProgressState -State $state -Event @{ Type = 'AppStarted'; Data = @{ AppId = 'app1' } }
        $state.RunningApps.Count | Should -Be 1
        
        # App 1 completes
        Update-ProgressState -State $state -Event @{ Type = 'AppCompleted'; Data = @{ AppId = 'app1'; Success = $true } }
        $state.CompletedCount | Should -Be 1
        $state.RunningApps.Count | Should -Be 0
        
        # App 2 starts
        Update-ProgressState -State $state -Event @{ Type = 'AppStarted'; Data = @{ AppId = 'app2' } }
        $state.RunningApps.Count | Should -Be 1
        
        # App 2 fails
        Update-ProgressState -State $state -Event @{ Type = 'AppCompleted'; Data = @{ AppId = 'app2'; Success = $false } }
        $state.CompletedCount | Should -Be 2
        $state.FailedCount | Should -Be 1
        $state.RunningApps.Count | Should -Be 0
    }
    
    It "Correctly tracks parallel app lifecycle" {
        $state = New-ProgressState -TotalApps 5 -ParallelThrottle 3
        
        # Start 3 apps in parallel
        Update-ProgressState -State $state -Event @{ Type = 'AppStarted'; Data = @{ AppId = 'app1' } }
        Update-ProgressState -State $state -Event @{ Type = 'AppStarted'; Data = @{ AppId = 'app2' } }
        Update-ProgressState -State $state -Event @{ Type = 'AppStarted'; Data = @{ AppId = 'app3' } }
        
        $state.RunningApps.Count | Should -Be 3
        $state.CompletedCount | Should -Be 0
        
        # Complete app1
        Update-ProgressState -State $state -Event @{ Type = 'AppCompleted'; Data = @{ AppId = 'app1'; Success = $true } }
        $state.RunningApps.Count | Should -Be 2
        $state.CompletedCount | Should -Be 1
        
        # Start app4
        Update-ProgressState -State $state -Event @{ Type = 'AppStarted'; Data = @{ AppId = 'app4' } }
        $state.RunningApps.Count | Should -Be 3
        
        # Complete app2 and app3
        Update-ProgressState -State $state -Event @{ Type = 'AppCompleted'; Data = @{ AppId = 'app2'; Success = $true } }
        Update-ProgressState -State $state -Event @{ Type = 'AppCompleted'; Data = @{ AppId = 'app3'; Success = $false } }
        
        $state.RunningApps.Count | Should -Be 1
        $state.CompletedCount | Should -Be 3
        $state.FailedCount | Should -Be 1
    }
}
