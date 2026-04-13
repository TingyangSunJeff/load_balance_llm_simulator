classdef EventScheduler < handle
    % EventScheduler - Discrete event simulation scheduler
    %
    % This class manages a priority queue of simulation events and provides
    % the core event-driven simulation framework for job scheduling.
    %
    % Event types:
    %   - 'arrival': Job arrival event
    %   - 'completion': Job completion event
    %   - 'custom': User-defined event
    
    properties (Access = private)
        event_queue     % Priority queue of events (sorted by time)
        current_time    % Current simulation time
        event_counter   % Counter for unique event IDs
    end
    
    methods
        function obj = EventScheduler()
            % Constructor for EventScheduler
            
            obj.event_queue = {};
            obj.current_time = 0;
            obj.event_counter = 0;
        end
        
        function event_id = schedule_event(obj, event_time, event_type, event_data)
            % Schedule a new event
            %
            % Args:
            %   event_time: Time when event should occur
            %   event_type: String type of event ('arrival', 'completion', 'custom')
            %   event_data: Struct with event-specific data
            %
            % Returns:
            %   event_id: Unique identifier for this event
            
            if event_time < obj.current_time
                error('Cannot schedule event in the past (current: %.3f, event: %.3f)', ...
                    obj.current_time, event_time);
            end
            
            obj.event_counter = obj.event_counter + 1;
            event_id = obj.event_counter;
            
            % Create event structure
            event = struct();
            event.id = event_id;
            event.time = event_time;
            event.type = event_type;
            event.data = event_data;
            
            % Insert event into priority queue (sorted by time)
            obj.insert_event(event);
        end
        
        function event = get_next_event(obj)
            % Get and remove the next event from the queue
            %
            % Returns:
            %   event: Next event struct, or empty if no events
            
            if isempty(obj.event_queue)
                event = [];
                return;
            end
            
            % Remove first event (earliest time)
            event = obj.event_queue{1};
            obj.event_queue(1) = [];
            
            % Update current time
            obj.current_time = event.time;
        end
        
        function event = peek_next_event(obj)
            % Look at next event without removing it
            %
            % Returns:
            %   event: Next event struct, or empty if no events
            
            if isempty(obj.event_queue)
                event = [];
            else
                event = obj.event_queue{1};
            end
        end
        
        function has_events = has_pending_events(obj)
            % Check if there are pending events
            %
            % Returns:
            %   has_events: True if events are pending
            
            has_events = ~isempty(obj.event_queue);
        end
        
        function time = get_current_time(obj)
            % Get current simulation time
            %
            % Returns:
            %   time: Current simulation time
            
            time = obj.current_time;
        end
        
        function count = get_event_count(obj)
            % Get number of pending events
            %
            % Returns:
            %   count: Number of events in queue
            
            count = length(obj.event_queue);
        end
        
        function success = cancel_event(obj, event_id)
            % Cancel a scheduled event
            %
            % Args:
            %   event_id: ID of event to cancel
            %
            % Returns:
            %   success: True if event was found and cancelled
            
            success = false;
            
            for i = 1:length(obj.event_queue)
                if obj.event_queue{i}.id == event_id
                    obj.event_queue(i) = [];
                    success = true;
                    break;
                end
            end
        end
        
        function clear_events(obj)
            % Clear all pending events
            
            obj.event_queue = {};
        end
        
        function reset_scheduler(obj)
            % Reset scheduler to initial state
            
            obj.event_queue = {};
            obj.current_time = 0;
            obj.event_counter = 0;
        end
        
        function display_queue(obj)
            % Display current event queue for debugging
            
            fprintf('Event Queue (current time: %.3f):\n', obj.current_time);
            if isempty(obj.event_queue)
                fprintf('  No pending events\n');
                return;
            end
            
            for i = 1:length(obj.event_queue)
                event = obj.event_queue{i};
                fprintf('  [%d] Time: %.3f, Type: %s\n', ...
                    event.id, event.time, event.type);
            end
        end
        
        function events = get_events_by_type(obj, event_type)
            % Get all events of a specific type
            %
            % Args:
            %   event_type: String type to filter by
            %
            % Returns:
            %   events: Cell array of matching events
            
            events = {};
            for i = 1:length(obj.event_queue)
                if strcmp(obj.event_queue{i}.type, event_type)
                    events{end + 1} = obj.event_queue{i};
                end
            end
        end
        
        function next_time = get_next_event_time(obj)
            % Get time of next event without processing it
            %
            % Returns:
            %   next_time: Time of next event, or inf if no events
            
            if isempty(obj.event_queue)
                next_time = inf;
            else
                next_time = obj.event_queue{1}.time;
            end
        end
    end
    
    methods (Access = private)
        function insert_event(obj, event)
            % Insert event into priority queue maintaining time order
            %
            % Args:
            %   event: Event struct to insert
            
            if isempty(obj.event_queue)
                obj.event_queue{1} = event;
                return;
            end
            
            % Find insertion point to maintain time ordering
            insert_pos = length(obj.event_queue) + 1;
            for i = 1:length(obj.event_queue)
                if event.time < obj.event_queue{i}.time
                    insert_pos = i;
                    break;
                elseif event.time == obj.event_queue{i}.time
                    % For events at same time, maintain FIFO order by ID
                    if event.id < obj.event_queue{i}.id
                        insert_pos = i;
                        break;
                    end
                end
            end
            
            % Insert event at correct position
            obj.event_queue = [obj.event_queue(1:insert_pos-1), {event}, ...
                              obj.event_queue(insert_pos:end)];
        end
    end
end