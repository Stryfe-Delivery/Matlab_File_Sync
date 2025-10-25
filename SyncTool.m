function folderSyncTool()
    % FOLDERSYNCTOOL - Enhanced with conflict resolution options
    
    % Create main figure
    fig = uifigure('Name', 'Folder Synchronization Tool', ...
                  'Position', [100 100 700 500]);
    
    % Set default paths
    mappedDrivePath = 'D:\temp';  % Modify to your mapped drive path
    workingDir = pwd;                      % Current working directory
    
    % Global settings - store in app data
    settings.applyToAll = false;
    settings.lastResolution = '';
    settings.resolutionMethod = 'prompt'; % Default resolution method
    setappdata(fig, 'settings', settings);
    
    % UI Components
    % Path displays
    uilabel(fig, 'Text', 'Mapped Drive:', 'Position', [20 470 100 20]);
    mappedDriveLabel = uilabel(fig, 'Text', mappedDrivePath, ...
                              'Position', [120 470 550 20]);
    
    uilabel(fig, 'Text', 'Working Directory:', 'Position', [20 440 100 20]);
    workingDirLabel = uilabel(fig, 'Text', workingDir, ...
                             'Position', [120 440 550 20]);
    
    % Folder selection listbox
    uilabel(fig, 'Text', 'Available Folders:', 'Position', [20 400 100 20]);
    folderList = uilistbox(fig, 'Position', [20 150 300 250], ...
                          'Multiselect', 'on');
    
    % Resolution dropdown
    resolutionDropdown = uidropdown(fig, ...
        'Position', [350 400 120 20], ...
        'Items', {'Prompt User', 'Newer Files', 'Larger Files', 'Skip All', 'Overwrite All'}, ...
        'ItemsData', {'prompt', 'newer', 'larger', 'skip', 'overwrite'}, ...
        'Value', 'prompt', ...
        'ValueChangedFcn', @changeResolutionMethod);

    % Refresh button
    refreshBtn = uibutton(fig, 'push', ...
                         'Text', 'Refresh List', ...
                         'Position', [20 110 100 30], ...
                         'ButtonPushedFcn', @refreshFolders);
    
    % Operation buttons
    pullBtn = uibutton(fig, 'push', ...
                      'Text', 'Pull Selected', ...
                      'Position', [350 300 100 30], ...
                      'ButtonPushedFcn', @pullFolders);
    
    pushBtn = uibutton(fig, 'push', ...
                      'Text', 'Push Selected', ...
                      'Position', [350 250 100 30], ...
                      'ButtonPushedFcn', @pushFolders);
    
    % Log console
    uilabel(fig, 'Text', 'Operation Log:', 'Position', [20 80 100 20]);
    logConsole = uitextarea(fig, 'Position', [20 20 650 60], ...
                           'Editable', 'off');
    
    % Store UI components in app data for access in callbacks
    setappdata(fig, 'logConsole', logConsole);
    setappdata(fig, 'folderList', folderList);
    setappdata(fig, 'mappedDrivePath', mappedDrivePath);
    setappdata(fig, 'workingDir', workingDir);
    
    % Initial folder refresh
    refreshFolders();
    
    %% Nested callback functions
    function changeResolutionMethod(dd, event)
        % Update resolution method based on dropdown selection
        settings = getappdata(fig, 'settings');
        settings.resolutionMethod = event.Value;
        setappdata(fig, 'settings', settings);
        
        logConsole = getappdata(fig, 'logConsole');
        methodNames = {'Prompt User', 'Newer Files', 'Larger Files', 'Skip All', 'Overwrite All'};
        methodValues = {'prompt', 'newer', 'larger', 'skip', 'overwrite'};
        selectedName = methodNames{strcmp(methodValues, event.Value)};
        addLog(['Conflict resolution changed to: ' selectedName]);
    end

    function refreshFolders(~, ~)
        % Refresh the list of folders
        mappedDrivePath = getappdata(fig, 'mappedDrivePath');
        workingDir = getappdata(fig, 'workingDir');
        folderList = getappdata(fig, 'folderList');
        
        try
            % Get folders from mapped drive
            mappedFolders = dir(mappedDrivePath);
            mappedFolders = mappedFolders([mappedFolders.isdir]);
            mappedFolders = mappedFolders(~ismember({mappedFolders.name}, {'.', '..'}));
            
            % Get folders from working directory
            localFolders = dir(workingDir);
            localFolders = localFolders([localFolders.isdir]);
            localFolders = localFolders(~ismember({localFolders.name}, {'.', '..'}));
            
            % Combine unique folder names
            allFolders = unique([{mappedFolders.name}, {localFolders.name}]);
            
            % Update listbox
            folderList.Items = allFolders;
            folderList.Value = {};
            
            addLog(sprintf('Folder list refreshed. Found %d folders.', length(allFolders)));
        catch ME
            addLog(sprintf('Error refreshing folders: %s', ME.message), true);
        end
    end

    function pullFolders(~, ~)
        % Pull selected folders from mapped drive to working directory
        operateOnFolders('pull');
    end

    function pushFolders(~, ~)
        % Push selected folders from working directory to mapped drive
        operateOnFolders('push');
    end

    function operateOnFolders(operation)
        % Handle both push and pull operations with conflict resolution
        folderList = getappdata(fig, 'folderList');
        mappedDrivePath = getappdata(fig, 'mappedDrivePath');
        workingDir = getappdata(fig, 'workingDir');
        
        selectedFolders = folderList.Value;
        
        if isempty(selectedFolders)
            addLog(sprintf('No folders selected for %s', operation), true);
            return;
        end
        
        % Reset settings for this operation
        settings = getappdata(fig, 'settings');
        settings.applyToAll = false;
        settings.lastResolution = '';
        setappdata(fig, 'settings', settings);
        
        for i = 1:length(selectedFolders)
            folder = selectedFolders{i};
            
            if strcmp(operation, 'pull')
                sourcePath = fullfile(mappedDrivePath, folder);
                destPath = fullfile(workingDir, folder);
                opLabel = 'Pulled';
            else
                sourcePath = fullfile(workingDir, folder);
                destPath = fullfile(mappedDrivePath, folder);
                opLabel = 'Pushed';
            end
            
            try
                if ~exist(sourcePath, 'dir')
                    addLog(sprintf('Source folder not found: %s', folder), true);
                    continue;
                end
                
                % Check if destination exists
                if exist(destPath, 'dir')
                    [result, action] = handleConflict(sourcePath, destPath);
                    
                    if strcmp(action, 'skip')
                        continue;
                    elseif strcmp(action, 'overwrite')
                        [status, message] = rmdir(destPath, 's');
                        if ~status
                            error('Failed to remove directory: %s', message);
                        end
                    end
                end
                
                % Perform the copy operation
                [status, message] = copyfile(sourcePath, destPath);
                if ~status
                    error('Copy failed: %s', message);
                end
                
                addLog(sprintf('%s folder: %s', opLabel, folder));
                
            catch ME
                addLog(sprintf('Error %s %s: %s', operation, folder, ME.message), true);
            end
        end
    end

    function [result, action] = handleConflict(source, destination)
        % Handle file conflicts based on selected resolution method
        settings = getappdata(fig, 'settings');
        action = 'skip'; % Default action
        
        if settings.applyToAll && ~isempty(settings.lastResolution)
            % Apply previous resolution decision
            action = settings.lastResolution;
            result = 'Applied previous resolution';
            return;
        end
        
        switch settings.resolutionMethod
            case 'prompt'
                % Show conflict resolution dialog
                [choice, applyAll] = conflictResolutionDialog(source, destination);
                
                if applyAll
                    settings.applyToAll = true;
                    settings.lastResolution = choice;
                    setappdata(fig, 'settings', settings);
                end
                
                action = choice;
                result = sprintf('User decided: %s', choice);
                
            case 'newer'
                % Automatically resolve based on modification date
                sourceInfo = dir(source);
                destInfo = dir(destination);
                
                if sourceInfo.datenum > destInfo.datenum
                    action = 'overwrite';
                    result = 'Source is newer - overwriting';
                else
                    action = 'skip';
                    result = 'Destination is newer - keeping';
                end
                
            case 'larger'
                % Automatically resolve based on size
                sourceSize = getFolderSize(source);
                destSize = getFolderSize(destination);
                
                if sourceSize > destSize
                    action = 'overwrite';
                    result = 'Source is larger - overwriting';
                else
                    action = 'skip';
                    result = 'Destination is larger - keeping';
                end
                
            case 'skip'
                action = 'skip';
                result = 'Skipping all conflicts';
                
            case 'overwrite'
                action = 'overwrite';
                result = 'Overwriting all conflicts';
        end
        
        addLog(result);
    end

    function [choice, applyAll] = conflictResolutionDialog(source, destination)
        % Create conflict resolution dialog
        d = uifigure('Name', 'Conflict Resolution', ...
                    'Position', [400 400 400 250], ...
                    'WindowStyle', 'modal');
        
        % Display conflict information
        sourceInfo = dir(source);
        destInfo = dir(destination);
        
        sourceSize = getFolderSize(source);
        destSize = getFolderSize(destination);
        
        infoText = sprintf(['Conflict detected:\\n\\n' ...
                           'Source: %s\\nModified: %s\\nSize: %s\\n\\n' ...
                           'Destination: %s\\nModified: %s\\nSize: %s'], ...
                          source, datestr(sourceInfo.datenum), ...
                          formatBytes(sourceSize), ...
                          destination, datestr(destInfo.datenum), ...
                          formatBytes(destSize));
        
        uilabel(d, 'Text', infoText, 'Position', [20 120 360 100], ...
                'Interpreter', 'none');
        
        % Resolution buttons
        overwriteBtn = uibutton(d, 'push', ...
                              'Text', 'Overwrite', ...
                              'Position', [20 70 80 30], ...
                              'ButtonPushedFcn', @(src,evt)closeDialog('overwrite'));
        
        keepBothBtn = uibutton(d, 'push', ...
                             'Text', 'Keep Both', ...
                             'Position', [110 70 80 30], ...
                             'ButtonPushedFcn', @(src,evt)closeDialog('keep_both'));
        
        skipBtn = uibutton(d, 'push', ...
                         'Text', 'Skip', ...
                         'Position', [200 70 80 30], ...
                         'ButtonPushedFcn', @(src,evt)closeDialog('skip'));
        
        % Apply to all checkbox
        applyCheckbox = uicheckbox(d, ...
                                 'Text', 'Apply to all remaining conflicts', ...
                                 'Position', [20 30 250 30]);
        
        % Wait for user decision
        choice = '';
        applyAll = false;
        uiwait(d);
        
        function closeDialog(selectedChoice)
            choice = selectedChoice;
            applyAll = applyCheckbox.Value;
            delete(d);
        end
    end

    function size = getFolderSize(folder)
        % Calculate total size of a folder
        files = dir(fullfile(folder, '**/*.*'));
        files = files(~[files.isdir]);
        if isempty(files)
            size = 0;
        else
            size = sum([files.bytes]);
        end
    end

    function str = formatBytes(bytes)
        % Format bytes into human-readable string
        if bytes < 1024
            str = sprintf('%d B', bytes);
        elseif bytes < 1024^2
            str = sprintf('%.1f KB', bytes/1024);
        elseif bytes < 1024^3
            str = sprintf('%.1f MB', bytes/(1024^2));
        else
            str = sprintf('%.1f GB', bytes/(1024^3));
        end
    end

    function addLog(message, isError)
        % Add message to log console
        if nargin < 2
            isError = false;
        end
        
        logConsole = getappdata(fig, 'logConsole');
        timestamp = datestr(now, 'HH:MM:SS');
        if isError
            message = sprintf('[ERROR] %s', message);
        else
            message = sprintf('%s', message);
        end
        
        currentLog = logConsole.Value;
        if iscell(currentLog)
            logConsole.Value = [currentLog; {sprintf('[%s] %s', timestamp, message)}];
        else
            logConsole.Value = {sprintf('[%s] %s', timestamp, message)};
        end
        drawnow; % Force UI update
    end

end % Main function end
