__includes ["bdi.nls" "communication.nls"]

breed [drivers driver]
breed [passengers passenger]
breed [dispatchers dispatcher]

globals
[
  grid-x-inc               ;; the amount of patches in between two roads in the x direction
  grid-y-inc               ;; the amount of patches in between two roads in the y direction
  acceleration             ;; the constant that controls how much a car speeds up or slows down by if
                           ;; it is to accelerate or decelerate
  phase                    ;; keeps track of the phase
  num-cars-stopped         ;; the number of cars that are stopped during a single pass thru the go procedure
  current-light            ;; the currently selected light
  goal-candidates

  ;; patch agentsets
  intersections ;; agentset containing the patches that are intersections
  roads         ;; agentset containing the patches that are roads
  intersection-patches

  roadsA
  roadsB

  upRoad
  leftRoad
  downRoad
  rightRoad

  semaphores
  semaphore-goals

  number-completed-trips
  number-cancel-trips
  number-shared-trips
  number-individual-trips

  total-number-passengers
  total-wait-time
  total-travel-time
  total-travel-distance
  total-ratio
]

drivers-own
[
  speed     ;; the speed of the turtle
  up-car?   ;; true if the turtle moves downwards and false if it moves to the right
  capacity
  current-path
  goal
  stops
  distances
  passenger-list

  passengers-number
  num-in-car

  intentions
  beliefs
  incoming-queue
  num-patches

  temp-passenger
  temp-proposal
]

passengers-own
[
  wait-time
  travel-time
  travel-distance
  optimal-travel-distance
  share-ride?
  max-pickup-ticks
  max-dropoff-ticks

  pick-up
  goal

  driver-car
  response-received
  has-ride?

  intentions
  beliefs
  incoming-queue
  number-responses

  temp-wait-time
  temp-travel-time
  temp-travel-distance

  wait-before-die
  num-tries
  wait-tries
]

dispatchers-own
[
  intentions
  incoming-queue
  processing-queue

  is-processing?
  collection-start-tick
]

patches-own
[
  intersection?   ;; true if the patch is at the intersection of two roads
  green-light-up? ;; true if the green light is above the intersection.  otherwise, false.
                  ;; false for a non-intersection patches.
  my-row          ;; the row of the intersection counting from the upper left corner of the
                  ;; world.  -1 for non-intersection patches.
  my-column       ;; the column of the intersection counting from the upper left corner of the
                  ;; world.  -1 for non-intersection patches.
  my-phase        ;; the phase for the intersection.  -1 for non-intersection patches.
  auto?           ;; whether or not this intersection will switch automatically.
                  ;; false for non-intersection patches.
  actual-color
]


;;;;;;;;;;;;;;;;;;;;;;
;; Setup Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Initialize the display by giving the global and patch variables initial values.
;; Create num-cars of turtles if there are enough road patches for one turtle to
;; be created per road patch. Set up the plots.
to setup
  clear-all
  setup-globals

  ;; First we ask the patches to draw themselves and set up a few variables
  setup-patches

  set-default-shape drivers "car"
  set-default-shape passengers "person"

  set goal-candidates patches with [
    pcolor = 38 and any? neighbors with [ pcolor = white ]
  ]
  set intersection-patches patches with [
    member? patch-at 0 1 intersections
    or
    member? patch-at -1 0 intersections
    or
    member? patch-at -1 1 intersections
    or
    member? patch-at 0 0 intersections
  ]

  if (num-drivers > count roads)
  [
    user-message (word "There are too many cars for the amount of "
                       "road.  Either increase the amount of roads "
                       "by increasing the GRID-SIZE-X or "
                       "GRID-SIZE-Y sliders, or decrease the "
                       "number of cars by lowering the NUMBER slider.\n"
                       "The setup has stopped.")
    stop
  ]

  ;; Create the drivers turtles
  create-drivers num-drivers
  [
    setup-drivers
    set-driver-color
    record-data
    setup-driver-goal

    set current-path get-path patch-here goal
    go-to-goal
  ]

  ;; Create the dispatcher
  if not distributed [
    create-dispatchers 1 [
      setup-dispatcher
    ]
  ]

  ;; give the turtles an initial speed
  ask drivers [ set-car-speed ]

  reset-ticks
  reset-timer
end

;; Setup if passenger wants to share ride or not
to setup-ride-choice
  ifelse (random 100) < share-ride-probability
  [
    set share-ride? true

  ][
    set share-ride? false
    set color magenta
  ]
end

;; Set randomnly pickup patch of passenger
;; Set randomnly drop off patch of passenger
to setup-goal
  set pick-up one-of goal-candidates
  set goal one-of goal-candidates with [ self != [ pick-up ] of myself ]
end

;; Set randomnly initial patch goal of driver (for when driver has no passengers)
to setup-driver-goal
  set goal one-of goal-candidates
end

;; Initialize the global variables to appropriate values
to setup-globals
  set current-light nobody ;; just for now, since there are no lights yet
  set phase 0
  set num-cars-stopped 0
  set number-completed-trips 0
  set grid-x-inc world-width / grid-size-x
  set grid-y-inc world-height / grid-size-y
  set total-number-passengers 0
  set total-wait-time 0
  set total-travel-time 0
  set total-travel-distance 0
  set total-ratio 0
  set number-cancel-trips 0

  ;; don't make acceleration 0.1 since we could get a rounding error and end up on a patch boundary
  set acceleration 0.099

end

;; Make the patches have appropriate colors, set up the roads and intersections agentsets,
;; and initialize the traffic lights to one setting
to setup-patches
  ;; initialize the patch-owned variables and color the patches to a base-color
  ask patches
  [
    set intersection? false
    set auto? false
    set green-light-up? true
    set my-row -1
    set my-column -1
    set my-phase -1
    set pcolor brown + 3
  ]

  ;; initialize the global variables that hold patch agentsets
  set roads patches with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0) or
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)
  ]
  set roadsA roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0)
  ]
  set roadsB roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) or
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)
  ]
  set upRoad roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0)
  ]
  set rightRoad roads with [
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0)
  ]
  set downRoad roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0)
  ]
  set leftRoad roads with [
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)
  ]
  set intersections roads with [
    (floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)
  ]
  set semaphores roads with [
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 2)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 3)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 0)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 1)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor + 2) mod grid-y-inc) = 1))
  ]
  set semaphore-goals roads with [
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 1)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor) mod grid-y-inc) = 2)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 3)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor - 1) mod grid-y-inc) = 0)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor + 1) mod grid-y-inc) = 1)) or
    ((floor ((pxcor + max-pxcor - floor (grid-x-inc - 2)) mod grid-x-inc) = 0) and
    (floor ((pycor + max-pycor + 2) mod grid-y-inc) = 1))
  ]
  ask roads [set pcolor white ]
  ask intersections [ set pcolor white ]

  setup-intersections
end

;; Give the intersections appropriate values for the intersection?, my-row, and my-column
;; patch variables.  Make all the traffic lights start off so that the lights are red
;; horizontally and green vertically.
to setup-intersections
  ask intersections
  [
    set intersection? true
    set green-light-up? true
    set my-phase 0
    set auto? true
    set my-row floor((pycor + max-pycor) / grid-y-inc)
    set my-column floor((pxcor + max-pxcor) / grid-x-inc)
    set-signal-colors
  ]
end

;; Initialize the driver variables to appropriate values and place the driver on an empty road patch.
to setup-drivers
  set speed 0
  set capacity 5
  set passengers-number 0
  set num-in-car 0
  set intentions []
  set incoming-queue []
  set stops []
  set distances []
  set temp-passenger -1
  set passenger-list []
  put-on-empty-road
  ifelse intersection?
  [
    ifelse random 2 = 0
    [ set up-car? true ]
    [ set up-car? false ]
  ]
  [
    ; if the turtle is on a vertical road (rather than a horizontal one)
    ifelse (floor((pxcor + max-pxcor - floor(grid-x-inc - 1)) mod grid-x-inc) = 0)
    [ set up-car? true ]
    [ set up-car? false ]
  ]
  ifelse up-car?
  [ set heading 180 ]
  [ set heading 90 ]
end

;; Initialize the passenger variables to appropriate values
to setup-passengers
  move-to pick-up

  set has-ride? false
  set response-received false
  set driver-car nobody
  set intentions []
  set incoming-queue []
  set number-responses 0
  set temp-wait-time 0
  set wait-time 0
  set wait-before-die 0
  set num-tries 0
  set wait-tries 0
  let path get-path one-of ([neighbors4] of patch-here) with [member? self roads] goal
  set optimal-travel-distance length path
  set-ticks-threshold
end

to set-ticks-threshold
  set max-pickup-ticks floor (ticks + (((random-float 4) + 1) * pickup-time-base-value))
  set max-dropoff-ticks floor (max-pickup-ticks + ((trip-time-threshold / 100) * get-optimal-travel-time one-of ([neighbors4] of patch-here) with [member? self roads] goal))
end

;; Initialize the dispatcher variables to appropriate values
to setup-dispatcher
  set intentions []
  set incoming-queue []
  set processing-queue []
  set is-processing? false
  set collection-start-tick 0
  hide-turtle
end

;; Find a road patch without any turtles on it and place the turtle there.
to put-on-empty-road  ;; turtle procedure
  move-to one-of roads with [not any? drivers-on self]
end


;;;;;;;;;;;;;;;;;;;;;;;;
;; Runtime Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;;;

;; Run the simulation
to go
  if (ticks >= 15000) [
    ;; export-all-plots "plots3-2.csv"
    stop
  ]
  ifelse show-labels [ask turtles [ set label who ]][ask turtles [ set label "" ]]

  ;; Create the passengers turtles
  if (ticks mod ceiling (1 / passenger-spawn-rate)) = 0 and (count passengers) < num-max-passengers [
    set total-number-passengers total-number-passengers + 1
    create-passengers 1
    [
      setup-goal
      set color black
      setup-ride-choice

      setup-passengers
      ask-for-ride
    ]
  ]

  ask turtles [execute-intentions]

  ;; have the intersections change their color
  set-signals
  set num-cars-stopped 0

  ;; set the turtles speed for this time thru the procedure, move them forward their speed,
  ;; record data for plotting, and set the color of the turtles to an appropriate color
  ;; based on their speed
  ask drivers [
    record-data
    set-driver-color
  ]

  ask passengers [
    if color = blue [
      if wait-before-die > 100 [
        die
      ]
      set wait-before-die wait-before-die + 1
    ]
  ]

  if not distributed [ ask dispatchers [ collect-msgs ] ]

  ;; update the phase and the global clock
  next-phase
  tick
end

;; have the traffic lights change color if phase equals each intersections' my-phase
to set-signals
  ask intersections with [auto? and phase = floor ((my-phase * ticks-per-cycle) / 100)]
  [
    set green-light-up? (not green-light-up?)
    set-signal-colors
  ]
end

;; This procedure checks the variable green-light-up? at each intersection and sets the
;; traffic lights to have the green light up or the green light to the left.
to set-signal-colors  ;; intersection (patch) procedure
  ifelse power? [
    ifelse green-light-up? [
      ask patch-at -1 -1 [ set pcolor red ]
      ask patch-at 2 0 [ set pcolor red ]
      ask patch-at 0 1 [ set pcolor green ]
      ask patch-at 1 -2 [ set pcolor green ]
    ]
    [
      ask patch-at -1 -1 [ set pcolor green ]
      ask patch-at 2 0 [ set pcolor green ]
      ask patch-at 0 1 [ set pcolor red ]
      ask patch-at 1 -2 [ set pcolor red ]
    ]
  ]
  [
    ask patch-at -1 -1 [ set pcolor white]
    ask patch-at 2 0 [ set pcolor white ]
    ask patch-at 0 1 [ set pcolor white ]
    ask patch-at 1 -2 [ set pcolor white ]
  ]
end

;; set the turtles' speed based on whether they are at a red traffic light or the speed of the
;; turtle (if any) on the patch in front of them
to set-car-speed  ;; turtle procedure
  ifelse pcolor = red
  [ set speed 0 ]
  [
    ifelse (member? patch-here roadsA) [
        ifelse (member? patch-here upRoad)
        [ set-speed 0 1 ]
        [ set-speed 1 0 ]
      ] [
        ifelse (member? patch-here downRoad)
        [ set-speed 0 -1 ]
        [ set-speed -1 0 ]
      ]
  ]
end

;; set the speed variable of the car to an appropriate value (not exceeding the
;; speed limit) based on whether there are cars on the patch in front of the car
to set-speed [ delta-x delta-y ]  ;; turtle procedure
  ;; get the turtles on the patch in front of the turtle
  let cars-ahead drivers-at delta-x delta-y

  ;; if there are turtles in front of the turtle, slow down
  ;; otherwise, speed up
  ifelse any? cars-ahead
  [
    ifelse any? (cars-ahead with [ up-car? != [up-car?] of myself ])
    [
      set speed 0
    ]
    [
      set speed [speed] of one-of cars-ahead
      slow-down
    ]
  ]
  [ speed-up ]
end

;; decrease the speed of the turtle
to slow-down  ;; turtle procedure
  ifelse speed <= 0  ;;if speed < 0
  [ set speed 0 ]
  [ set speed speed - acceleration ]
end

;; increase the speed of the turtle
to speed-up  ;; turtle procedure
  ifelse speed > speed-limit
  [ set speed speed-limit ]
  [ set speed speed + acceleration ]
end

;; set the color of the turtle to a different color based on how fast the turtle is moving
to set-driver-color  ;; turtle procedure
  ifelse speed < (speed-limit / 2)
  [ set color blue ]
  [ set color cyan - 2 ]
end

;; keep track of the number of stopped turtles and the amount of time a turtle has been stopped
;; if its speed is 0
to record-data  ;; turtle procedure
  if speed = 0
  [
    set num-cars-stopped num-cars-stopped + 1
  ]
end

to change-current
  ask current-light
  [
    set green-light-up? (not green-light-up?)
    set-signal-colors
  ]
end

;; cycles phase to the next appropriate value
to next-phase
  ;; The phase cycles from 0 to ticks-per-cycle, then starts over.
  set phase phase + 1
  if phase mod ticks-per-cycle = 0
    [ set phase 0 ]
end

;; Passenger waits for messages and responds to drivers
to wait-for-messages-passenger
  set wait-tries wait-tries + 1
  if (wait-tries >= 600 and distributed) [
    set num-tries num-tries + 1
    set wait-tries 0
  ]
  if (num-tries >= 3) [
    set number-cancel-trips number-cancel-trips + 1
    die
    stop
  ]

  ifelse distributed [
    ifelse number-responses < count drivers [
    let msg get-message
    if msg = "no_message" [stop]
    set number-responses number-responses + 1
    let sender get-sender msg
    if get-performative msg = "propose" [
      ifelse driver-car = nobody [
        let pickup-ticks first get-content msg
        let dropoff-ticks item 1 get-content msg
        ifelse (pickup-ticks <= max-pickup-ticks and dropoff-ticks <= max-dropoff-ticks) [
          ifelse share-ride? [
            set color orange
          ][
            set color pink
          ]
          set driver-car turtle (read-from-string sender)
          send create-reply "accept" msg
          set wait-tries 0
          set response-received true
        ][
          send create-reply "reject" msg
        ]
      ][
        send create-reply "reject" msg
      ]
    ]
  ][
    set response-received true
    set num-tries num-tries + 1
  ]
  ][
    ifelse number-responses < 1 [
      let msg get-message
      if msg = "no_message" [stop]
      set number-responses number-responses + 1
      (ifelse get-performative msg = "inform" [
        if driver-car = nobody [
          let driver-number get-content msg
          ifelse share-ride? [
            set color orange
          ][
            set color pink
          ]
          set driver-car turtle driver-number
          set wait-tries 0
          set response-received true
        ]
      ] get-performative msg = "reject" [
        set response-received true
        set num-tries num-tries + 1
      ])
    ][
      set response-received true
      set num-tries num-tries + 1
    ]
  ]
end

;; Driver waits for messages and responds passengers
to wait-for-messages-driver
  let msg get-message-no-remove
  if msg = "no_message" [stop]
  let sender get-sender msg

  if (turtle (read-from-string sender) = nobody) [stop]

  ifelse distributed [
    (ifelse get-performative msg = "callforproposal" and get-content msg = "share" and temp-passenger = -1 [
      ifelse (passengers-number + 1 < capacity) [
        ifelse has-alone-passenger [
          set temp-proposal get-driver-proposal-alone sender stops who
        ][
          set temp-proposal get-best-driver-proposal sender stops who
        ]
        ifelse not (temp-proposal = []) [
          let proposal-ticks bf temp-proposal
          send add-content proposal-ticks create-reply "propose" msg
          set passengers-number passengers-number + 1
          set temp-passenger read-from-string sender
        ][
          send create-reply "reject" msg
        ]

      ][
        send create-reply "reject" msg
      ]
      remove-msg
    ] get-performative msg = "callforproposal" and get-content msg = "alone" and temp-passenger = -1 [
      ifelse (passengers-number + 1 < capacity) [
        set temp-proposal get-driver-proposal-alone sender stops who
        let proposal-ticks bf temp-proposal
        send add-content proposal-ticks create-reply "propose" msg
        set passengers-number passengers-number + 1
        set temp-passenger read-from-string sender
      ][
        send create-reply "reject" msg
      ]
      remove-msg
    ] get-performative msg = "accept" and temp-passenger = read-from-string sender [
      let number (read-from-string sender)
      set stops item 0 temp-proposal
      set passenger-list fput read-from-string sender passenger-list
      set temp-passenger -1
      set-path
      remove-msg
    ] get-performative msg = "reject" and temp-passenger = read-from-string sender [
      set passengers-number passengers-number - 1
      set temp-passenger -1
      remove-msg
    ])
  ][
    (ifelse get-performative msg = "propose" [
      set stops (item 0 get-content msg)
      set passenger-list fput (item 1 get-content msg) passenger-list
      set-path
      remove-msg
    ] get-performative msg = "reject" [
      remove-msg
    ])
  ]

  if get-performative msg = "inform" [
    if (get-content msg = "dropped-off") [
      set passenger-list remove read-from-string sender passenger-list
      set passengers-number passengers-number - 1
      set num-in-car num-in-car - 1
    ]
    if (get-content msg = "picked-up") [
      set num-in-car num-in-car + 1
    ]
    remove-msg
  ]
end

;; Add find a ride intention to passenger
to ask-for-ride
  add-intention "find-a-ride" "ride-found"
end

;; Check if a driver can pick (me) a passenger up
to pick-me-up
  ;; discard any messages
  if (color = blue) [stop]
  let msg get-message
  if msg != "no_message" and get-performative msg = "propose" [
    send create-reply "reject" msg
  ]

  let pickable-group [neighbors4] of driver-car
  if member? patch-here pickable-group [
    hide-turtle
  ]
end

;; Check if a driver can drop (me) a passenger off
to leave-me-there
  let pickable-group [neighbors4] of driver-car
  if member? goal pickable-group [
    move-to goal
    set shape "person"
    show-turtle
    set has-ride? true
  ]
end

;; Executes when intention find a ride is added
;; Passenger requests trip and waits for messages from drivers
to find-a-ride
  ifelse driver-car != nobody [
    add-intention "pick-me-up" "picked-up"
  ][
    ;; show "restarting waiting for msgs"
    set temp-wait-time ticks
    set-ticks-threshold
    set number-responses 0
    set response-received false
    add-intention "wait-for-messages-passenger" "response-was-received"
    let msg create-message "callforproposal"
    ifelse share-ride? [
      set msg add-content "share" msg
    ][
      set msg add-content "alone" msg
    ]
    ifelse distributed [
      broadcast-to drivers msg
    ][
      broadcast-to dispatchers msg
    ]
  ]
end

;; Add intention to drivers to move to next patch in path to current goal
to go-to-goal
  add-intention "next-patch-to-goal" "at-goal"
end

;; IDK
to collect-msgs
  (ifelse not is-processing? and ticks > collection-start-tick + 75 [
    start-processing
  ] is-processing? [
    process-messages
  ])
end

to start-processing
  set collection-start-tick ticks
  set is-processing? true
  set processing-queue incoming-queue
  set incoming-queue []
end

to process-messages
  let taken-drivers []
  let waiting-processing map [[msg] -> get-sender msg] processing-queue
  let all-proposals reduce [[acc curr-msg] -> ifelse-value empty? curr-msg [[]] [sentence acc get-proposals-for-message curr-msg]] fput [] processing-queue
  let sorted-proposals sort-by sort-proposal all-proposals
  while [not empty? sorted-proposals] [
    let proposal first sorted-proposals
    let proposal-passenger item 1 proposal
    let proposal-driver item 2 proposal
    if (not (member? proposal-driver taken-drivers)) and (member? (word proposal-passenger) waiting-processing) [
      set taken-drivers lput proposal-driver taken-drivers
      set waiting-processing remove (word proposal-passenger) waiting-processing
      send add-receiver proposal-driver add-content (list first (item 0 proposal) proposal-passenger) create-message "propose"
      send add-receiver proposal-passenger add-content proposal-driver create-message "inform"
    ]
    set sorted-proposals remove-item 0 sorted-proposals
  ]
  foreach waiting-processing [
    [message] ->
    send add-receiver (read-from-string message) create-message "reject"
  ]
  set processing-queue []
  set is-processing? false
end

to-report get-proposals-for-message [msg]
  let proposal-passenger (read-from-string get-sender msg)
  let proposals []
  carefully [
    set proposals map [[proposal-driver] -> get-best-proposal-for-passenger-driver [who] of proposal-driver proposal-passenger] ([self] of drivers)
    set proposals filter [x -> not (x = "")] proposals
  ][
    set proposals []
  ]
  report proposals
end

to-report sort-proposal [p1 p2]
  let prop1 first p1
  let prop2 first p2
  report (last prop1) < (last prop2) ;; use last proposal ticks
end

to-report get-best-proposal-for-passenger-driver [proposal-driver proposal-passenger]
  let proposal []
  ifelse ([passengers-number] of turtle proposal-driver) + 1 < [capacity] of turtle proposal-driver [
    ifelse [share-ride?] of turtle proposal-passenger and not ([has-alone-passenger] of turtle proposal-driver) [
      set proposal get-best-driver-proposal (word proposal-passenger) [stops] of turtle proposal-driver proposal-driver
      if proposal = [] [
        report ""
      ]
    ][
      set proposal get-driver-proposal-alone (word proposal-passenger) [stops] of turtle proposal-driver proposal-driver
    ]
  ][
    report ""
  ]
  report (list proposal proposal-passenger proposal-driver)
end

;; Sets driver's current path
to set-path
  ifelse (empty? stops) [
    set goal one-of goal-candidates
  ][
    set goal (item 0 (item 0 stops))
  ]
  set current-path get-path patch-here goal
  go-to-goal
end

;; Executes when intention next patch to goal is added
to next-patch-to-goal
  wait-for-messages-driver
  face next-patch
  set-car-speed
  fd speed
end

;; Return driver's path next patch
to-report next-patch
  let choice item 0 current-path

  report choice
end

;; Compute path between driver current position and current goal
to-report get-path [start finish]
  let path []
  set path lput start path
  while [last path != finish] [
    let current-patch last path
    let patch-to-analyze current-patch
    let index 1
    while [not member? patch-to-analyze semaphores] [
      if (member? patch-to-analyze [ neighbors4 ] of finish) [
        set path lput patch-to-analyze path
        report path
      ]
      set patch-to-analyze ifelse-value (member? patch-to-analyze roadsA) [
        ifelse-value (member? patch-to-analyze upRoad)
        [ ([patch-at 0 index] of current-patch) ]
        [ ([patch-at index 0] of current-patch) ]
      ] [
        ifelse-value (member? patch-to-analyze downRoad)
        [ ([patch-at 0 (index * -1)] of current-patch) ]
        [ ([patch-at (index * -1) 0] of current-patch) ]
      ]
      set index index + 1
      set path lput patch-to-analyze path
    ]

    let intersection (patch-set [patch-at -1 2] of patch-to-analyze [patch-at 1 1] of patch-to-analyze [patch-at -2 0] of patch-to-analyze [patch-at 0 -1] of patch-to-analyze) with [member? self intersections]
    let possible-goals (patch-set [patch-at 1 1] of intersection [patch-at 0 -2] of intersection [patch-at -1 0] of intersection [patch-at 2 -1] of intersection)
    let current-choices possible-goals with [ not member? self path or member? self intersection-patches ]
    let semaphore-goal min-one-of current-choices [ distance finish]

    set path get-path-at-intersection path patch-to-analyze semaphore-goal
  ]
  report path
end

;; Checks if driver is at current goal
;; If true intention go to goal is completed
to-report at-goal
  if patch-here = (item 0 current-path) [
    if member? patch-here [neighbors4] of goal [
      if (not empty? stops) [
        set stops remove-item 0 stops
        ;; set distances remove-item 0 distances
      ]
      set-path
      report true
    ]
    set current-path but-first current-path
    set num-patches num-patches + 1
    go-to-goal
    report true
  ]
  report false
end

;; Checks if passenger received response
;; If true wait-for-messages-passenger intention is completed
to-report response-was-received
  report response-received
end

;; Checks if passenger already has an assigned ride
;; If true intention find-a-ride is completed
to-report  ride-found
  report has-ride?
end

;; Checks if passenger was picked up by driver
;; If true pick-me-up intention is completed
to-report picked-up
  if (hidden?) [
    set wait-time (ticks - temp-wait-time)
    set total-wait-time total-wait-time + wait-time
    set temp-travel-time ticks
    set temp-travel-distance [num-patches] of driver-car
    add-intention "leave-me-there" "dropped-off"
    send add-receiver ([who] of driver-car) add-content "picked-up" create-message "inform"
    report true
  ]
  report false
end

;; Checks if passenger was dropped off by driver
;; If true leave-me-there intention is completed
to-report dropped-off
  if (hidden? = false) [
    set travel-time (ticks - temp-travel-time)
    set total-travel-time total-travel-time + travel-time
    ;;show travel-time
    set travel-distance [num-patches] of driver-car - temp-travel-distance
    set total-travel-distance total-travel-distance + travel-distance
    set total-ratio total-ratio + (travel-distance / optimal-travel-distance)
    ;;show travel-distance
    send add-receiver ([who] of driver-car) add-content "dropped-off" create-message "inform"
    set color blue
    set number-completed-trips number-completed-trips + 1
    ifelse share-ride? = true
    [
      set number-shared-trips number-shared-trips + 1
    ][
      set number-individual-trips number-individual-trips + 1
    ]
    report true
  ]
  report false
end

;; Auxiliary function to get-path
to-report get-path-at-intersection [intersection-path current-patch goal-patch]
  let candidates ifelse-value (member? current-patch roadsA) [
     ifelse-value (member? current-patch upRoad)
    [(patch-set current-patch  ([patch-at 0 1] of current-patch) ([patch-at 0 2] of current-patch))]
     [(patch-set current-patch ([patch-at 1 0] of current-patch) ([patch-at 2 0] of current-patch))]
  ][
    ifelse-value (member? current-patch downRoad)
    [(patch-set current-patch ([patch-at 0 -1] of current-patch) ([patch-at 0 -2] of current-patch))]
    [(patch-set current-patch ([patch-at -1 0] of current-patch) ([patch-at -2 0] of current-patch))]
  ]
  let direction ifelse-value (member? current-patch roadsA) [
     ifelse-value (member? current-patch upRoad)
    ["up"]
     ["right"]
  ][
    ifelse-value (member? current-patch downRoad)
    ["down"]
    ["left"]
  ]

  let patch-to-analyze current-patch
  while [patch-to-analyze != goal-patch][
    ifelse member? patch-to-analyze candidates and patch-to-analyze != min-one-of candidates [ distance [ goal-patch ] of self ][
      ifelse (direction = "up" or direction = "right") [
        ifelse (direction = "up")
        [ set intersection-path lput ([patch-at 0 1] of patch-to-analyze) intersection-path ]
        [ set intersection-path lput ([patch-at 1 0] of patch-to-analyze) intersection-path ]
      ] [
        ifelse (direction = "down")
        [ set intersection-path lput ([patch-at 0 -1] of patch-to-analyze) intersection-path ]
        [ set intersection-path lput ([patch-at -1 0] of patch-to-analyze) intersection-path ]
      ]
    ][
      let next ifelse-value (member? patch-to-analyze ([neighbors4] of goal-patch))
      [ goal-patch ]
      [ min-one-of ([neighbors4] of patch-to-analyze) [ distance [ goal-patch ] of self ] ]
      set intersection-path lput next intersection-path
    ]
    set patch-to-analyze last intersection-path
  ]
  report intersection-path
end

;; Returns number of drivers with maximum capacity
to-report get-number-drivers-max
  let num 0
  ask drivers [
    if num-in-car + 1 = capacity [
      set num num + 1
    ]
  ]
  report num
end

to-report get-best-driver-proposal [sender cur-stops driver-number]
  let sender-number (read-from-string sender)
  let pickup (list [pick-up] of turtle sender-number sender-number "pickup")
  let dropoff (list [goal] of turtle sender-number sender-number "dropoff")

  let best-proposal []
  let best-proposal-pickup-ticks -1
  let best-proposal-dropoff-ticks -1
  let best-proposal-last-ticks -1

  let i 0 ;; pickup index
  let j 0 ;; dropoff index

  repeat (length cur-stops) + 1 [ ;; loop for pickup
    let temp-pickup-stops insert-item i cur-stops pickup
    set j i + 1
    repeat (length cur-stops + 1) - i [ ;; loop for dropoff
      let temp-dropoff-stops insert-item j temp-pickup-stops dropoff
      let stops-ticks get-stops-ticks temp-dropoff-stops [patch-here] of turtle driver-number

      let proposal-pickup-ticks item i stops-ticks
      let proposal-dropoff-ticks item j stops-ticks
      let proposal-last-ticks last stops-ticks

      if is-proposal-valid temp-dropoff-stops stops-ticks [
        ifelse distributed [
          if (best-proposal-dropoff-ticks = -1 or proposal-dropoff-ticks < best-proposal-dropoff-ticks) [
            set best-proposal temp-dropoff-stops
            set best-proposal-pickup-ticks proposal-pickup-ticks
            set best-proposal-dropoff-ticks proposal-dropoff-ticks
            set best-proposal-last-ticks proposal-last-ticks
          ]
        ][
          if (best-proposal-last-ticks = -1 or proposal-last-ticks < best-proposal-last-ticks) [
            set best-proposal temp-dropoff-stops
            set best-proposal-pickup-ticks proposal-pickup-ticks
            set best-proposal-dropoff-ticks proposal-dropoff-ticks
            set best-proposal-last-ticks proposal-last-ticks
          ]
        ]

      ]
      set j j + 1
    ]
    set i i + 1
  ]

  report ifelse-value empty? best-proposal [[]] [(list best-proposal best-proposal-pickup-ticks best-proposal-dropoff-ticks best-proposal-last-ticks)]
end

to-report get-driver-proposal-alone [sender cur-stops driver-number]
  let proposal cur-stops
  let sender-number (read-from-string sender)
  set proposal lput (list [pick-up] of turtle sender-number sender-number "pickup") proposal
  set proposal lput (list [goal] of turtle sender-number sender-number "dropoff") proposal
  let stops-ticks get-stops-ticks proposal [patch-here] of turtle driver-number

  let proposal-pickup-ticks last bl stops-ticks
  let proposal-dropoff-ticks last stops-ticks
  let proposal-last-ticks last stops-ticks

  report (list proposal proposal-pickup-ticks proposal-dropoff-ticks proposal-last-ticks)
end

to-report get-stops-ticks [stops-list curr-patch]
  let t ticks
  let last-patch curr-patch
  let stops-ticks []
  let i 0
  repeat length stops-list [
    let curr-stop item i stops-list
    let stop-patch item 0 curr-stop
    let p get-path last-patch stop-patch
    let curr-stop-ticks t + floor (length p / speed-limit)
    set stops-ticks lput curr-stop-ticks stops-ticks
    set t curr-stop-ticks
    set last-patch last p
    set i i + 1
  ]
  report stops-ticks
end

to-report get-optimal-travel-time [pickup dropoff]
  let p get-path pickup dropoff
  report floor (length p / speed-limit)
end

to-report is-proposal-valid [proposal-stops proposal-ticks]
  let i 0
  repeat length proposal-stops [
    let curr-stop item i proposal-stops
    let curr-ticks item i proposal-ticks

    let passenger-number item 1 curr-stop
    let stop-type item 2 curr-stop

    ifelse stop-type = "dropoff" [
      if (turtle passenger-number != nobody) and (curr-ticks > [max-dropoff-ticks] of turtle passenger-number) [
        report false
      ]
    ][
      if (turtle passenger-number != nobody) and (curr-ticks > [max-pickup-ticks] of turtle passenger-number) [
        report false
      ]
    ]

    set i i + 1
  ]
  report true
end

to-report has-alone-passenger
  let has-alone false
  foreach passenger-list [
    [number] ->
    if [share-ride?] of turtle number = false [
      set has-alone true
    ]
  ]
  report has-alone
end

; Copyright 2003 Uri Wilensky.
; See Info tab for full copyright and license.
@#$#@#$#@
GRAPHICS-WINDOW
309
34
911
637
-1
-1
16.0541
1
12
1
1
1
0
1
1
1
-18
18
-18
18
1
1
1
ticks
30.0

PLOT
923
269
1235
433
Average Travel Time for Passengers
Time
Average Travel Time
0.0
100.0
0.0
5.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-travel-time / number-completed-trips"

PLOT
922
94
1234
259
Ratio between shared rides and individual rides
Time
shared/individual
0.0
100.0
0.0
1.0
true
false
"set-plot-y-range 0 5" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (number-shared-trips) / (number-individual-trips)"

SLIDER
108
35
205
68
grid-size-y
grid-size-y
1
9
9.0
1
1
NIL
HORIZONTAL

SLIDER
12
35
106
68
grid-size-x
grid-size-x
1
9
9.0
1
1
NIL
HORIZONTAL

SWITCH
13
147
108
180
power?
power?
0
1
-1000

SLIDER
12
71
293
104
num-drivers
num-drivers
1
100
40.0
1
1
NIL
HORIZONTAL

PLOT
924
445
1236
609
Occupancy percentage
Time
Percentage
0.0
100.0
0.0
100.0
true
false
"set-plot-y-range 0 100" ""
PENS
"default" 1.0 0 -16777216 true "" "plot (mean [num-in-car / (capacity - 1)] of drivers) * 100"

BUTTON
227
200
291
233
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
208
35
292
68
Setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
12
222
166
255
speed-limit
speed-limit
0.1
1
0.1
0.1
1
NIL
HORIZONTAL

MONITOR
188
147
293
192
Current Phase
phase
3
1
11

SLIDER
13
185
167
218
ticks-per-cycle
ticks-per-cycle
1
100
10.0
1
1
NIL
HORIZONTAL

SLIDER
12
109
294
142
num-max-passengers
num-max-passengers
0
100
70.0
1
1
NIL
HORIZONTAL

SWITCH
13
458
170
491
show_messages
show_messages
1
1
-1000

SWITCH
13
496
171
529
show-intentions
show-intentions
1
1
-1000

SLIDER
12
261
292
294
share-ride-probability
share-ride-probability
0
100
40.0
1
1
NIL
HORIZONTAL

SLIDER
12
300
293
333
trip-time-threshold
trip-time-threshold
100
500
200.0
1
1
NIL
HORIZONTAL

SWITCH
13
420
168
453
distributed
distributed
0
1
-1000

MONITOR
921
36
1234
81
Number of completed trips
number-completed-trips
17
1
11

PLOT
1249
93
1560
259
Average Wait Time for Passengers
Time
Average Wait Time
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-wait-time / number-completed-trips"

PLOT
1248
268
1562
431
Average ratio TD/OTD
Time
TD/OTD
0.0
10.0
0.0
1.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-ratio / number-completed-trips"

SLIDER
13
378
293
411
passenger-spawn-rate
passenger-spawn-rate
0.001
1
0.1
0.001
1
NIL
HORIZONTAL

PLOT
1248
443
1563
609
Average Ride Distance
Time
Average Travel Distance
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-travel-distance / number-completed-trips"

MONITOR
1249
36
1560
81
Number of canceled trips
number-cancel-trips
17
1
11

SWITCH
14
535
146
568
show-labels
show-labels
1
1
-1000

SLIDER
13
339
292
372
pickup-time-base-value
pickup-time-base-value
100
500
200.0
50
1
NIL
HORIZONTAL

MONITOR
1569
93
1838
138
Ratio between shared and individual rides
(number-shared-trips) / (number-individual-trips)
17
1
11

MONITOR
1570
149
1691
194
Average wait time
total-wait-time / number-completed-trips
17
1
11

MONITOR
1570
204
1702
249
Average travel time
total-travel-time / number-completed-trips
17
1
11

MONITOR
1571
260
1722
305
Average ratio TD/OTD
total-ratio / number-completed-trips
17
1
11

MONITOR
1570
313
1725
358
Occupancy percentage
(mean [num-in-car / (capacity - 1)] of drivers) * 100
17
1
11

MONITOR
1571
366
1718
411
Average ride distance
total-travel-distance / number-completed-trips
17
1
11

@#$#@#$#@
## WHAT IS IT?

This is a model of traffic moving in a city grid. It allows you to control traffic lights and global variables, such as the speed limit and the number of cars, and explore traffic dynamics.

Try to develop strategies to improve traffic and to understand the different ways to measure the quality of traffic.

## HOW IT WORKS

Each time step, the cars attempt to move forward at their current speed.  If their current speed is less than the speed limit and there is no car directly in front of them, they accelerate.  If there is a slower car in front of them, they match the speed of the slower car and deccelerate.  If there is a red light or a stopped car in front of them, they stop.

There are two different ways the lights can change.  First, the user can change any light at any time by making the light current, and then clicking CHANGE LIGHT.  Second, lights can change automatically, once per cycle.  Initially, all lights will automatically change at the beginning of each cycle.

## HOW TO USE IT

Change the traffic grid (using the sliders GRID-SIZE-X and GRID-SIZE-Y) to make the desired number of lights.  Change any other of the settings that you would like to change.  Press the SETUP button.

At this time, you may configure the lights however you like, with any combination of auto/manual and any phase. Changes to the state of the current light are made using the CURRENT-AUTO?, CURRENT-PHASE and CHANGE LIGHT controls.  You may select the current intersection using the SELECT INTERSECTION control.  See below for details.

Start the simulation by pressing the GO button.  You may continue to make changes to the lights while the simulation is running.

### Buttons

SETUP - generates a new traffic grid based on the current GRID-SIZE-X and GRID-SIZE-Y and NUM-CARS number of cars.  This also clears all the plots. All lights are set to auto, and all phases are set to 0.
GO - runs the simulation indefinitely
CHANGE LIGHT - changes the direction traffic may flow through the current light. A light can be changed manually even if it is operating in auto mode.
SELECT INTERSECTION - allows you to select a new "current" light. When this button is depressed, click in the intersection which you would like to make current. When you've selected an intersection, the "current" label will move to the new intersection and this button will automatically pop up.

### Sliders

SPEED-LIMIT - sets the maximum speed for the cars
NUM-CARS - the number of cars in the simulation (you must press the SETUP button to see the change)
TICKS-PER-CYCLE - sets the number of ticks that will elapse for each cycle.  This has no effect on manual lights.  This allows you to increase or decrease the granularity with which lights can automatically change.
GRID-SIZE-X - sets the number of vertical roads there are (you must press the SETUP button to see the change)
GRID-SIZE-Y - sets the number of horizontal roads there are (you must press the SETUP button to see the change)
CURRENT-PHASE - controls when the current light changes, if it is in auto mode. The slider value represents the percentage of the way through each cycle at which the light should change. So, if the TICKS-PER-CYCLE is 20 and CURRENT-PHASE is 75%, the current light will switch at tick 15 of each cycle.

### Switches

POWER? - toggles the presence of traffic lights
CURRENT-AUTO? - toggles the current light between automatic mode, where it changes once per cycle (according to CURRENT-PHASE), and manual, in which you directly control it with CHANGE LIGHT.

### Plots

STOPPED CARS - displays the number of stopped cars over time
AVERAGE SPEED OF CARS - displays the average speed of cars over time
AVERAGE WAIT TIME OF CARS - displays the average time cars are stopped over time

## THINGS TO NOTICE

When cars have stopped at a traffic light, and then they start moving again, the traffic jam will move backwards even though the cars are moving forwards.  Why is this?

When POWER? is turned off and there are quite a few cars on the roads, "gridlock" usually occurs after a while.  In fact, gridlock can be so severe that traffic stops completely.  Why is it that no car can move forward and break the gridlock?  Could this happen in the real world?

Gridlock can occur when the power is turned on, as well.  What kinds of situations can lead to gridlock?

## THINGS TO TRY

Try changing the speed limit for the cars.  How does this affect the overall efficiency of the traffic flow?  Are fewer cars stopping for a shorter amount of time?  Is the average speed of the cars higher or lower than before?

Try changing the number of cars on the roads.  Does this affect the efficiency of the traffic flow?

How about changing the speed of the simulation?  Does this affect the efficiency of the traffic flow?

Try running this simulation with all lights automatic.  Is it harder to make the traffic move well using this scheme than controlling one light manually?  Why?

Try running this simulation with all lights automatic.  Try to find a way of setting the phases of the traffic lights so that the average speed of the cars is the highest.  Now try to minimize the number of stopped cars.  Now try to decrease the average wait time of the cars.  Is there any correlation between these different metrics?

## EXTENDING THE MODEL

Currently, the maximum speed limit (found in the SPEED-LIMIT slider) for the cars is 1.0.  This is due to the fact that the cars must look ahead the speed that they are traveling to see if there are cars ahead of them.  If there aren't, they speed up.  If there are, they slow down.  Looking ahead for a value greater than 1 is a little bit tricky.  Try implementing the correct behavior for speeds greater than 1.

When a car reaches the edge of the world, it reappears on the other side.  What if it disappeared, and if new cars entered the city at random locations and intervals?

## NETLOGO FEATURES

This model uses two forever buttons which may be active simultaneously, to allow the user to select a new current intersection while the model is running.

It also uses a chooser to allow the user to choose between several different possible plots, or to display all of them at once.

## RELATED MODELS

- "Traffic Basic": a simple model of the movement of cars on a highway.

- "Traffic Basic Utility": a version of "Traffic Basic" including a utility function for the cars.

- "Traffic Basic Adaptive": a version of "Traffic Basic" where cars adapt their acceleration to try and maintain a smooth flow of traffic.

- "Traffic Basic Adaptive Individuals": a version of "Traffic Basic Adaptive" where each car adapts individually, instead of all cars adapting in unison.

- "Traffic 2 Lanes": a more sophisticated two-lane version of the "Traffic Basic" model.

- "Traffic Intersection": a model of cars traveling through a single intersection.

- "Traffic Grid Goal": a version of "Traffic Grid" where the cars have goals, namely to drive to and from work.

- "Gridlock HubNet": a version of "Traffic Grid" where students control traffic lights in real-time.

- "Gridlock Alternate HubNet": a version of "Gridlock HubNet" where students can enter NetLogo code to plot custom metrics.

## HOW TO CITE

If you mention this model or the NetLogo software in a publication, we ask that you include the citations below.

For the model itself:

* Wilensky, U. (2003).  NetLogo Traffic Grid model.  http://ccl.northwestern.edu/netlogo/models/TrafficGrid.  Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

Please cite the NetLogo software as:

* Wilensky, U. (1999). NetLogo. http://ccl.northwestern.edu/netlogo/. Center for Connected Learning and Computer-Based Modeling, Northwestern University, Evanston, IL.

## COPYRIGHT AND LICENSE

Copyright 2003 Uri Wilensky.

![CC BY-NC-SA 3.0](http://ccl.northwestern.edu/images/creativecommons/byncsa.png)

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 License.  To view a copy of this license, visit https://creativecommons.org/licenses/by-nc-sa/3.0/ or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

Commercial licenses are also available. To inquire about commercial licenses, please contact Uri Wilensky at uri@northwestern.edu.

This model was created as part of the projects: PARTICIPATORY SIMULATIONS: NETWORK-BASED DESIGN FOR SYSTEMS LEARNING IN CLASSROOMS and/or INTEGRATED SIMULATION AND MODELING ENVIRONMENT. The project gratefully acknowledges the support of the National Science Foundation (REPP & ROLE programs) -- grant numbers REC #9814682 and REC-0126227.

<!-- 2003 -->
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
true
0
Polygon -7500403 true true 180 15 164 21 144 39 135 60 132 74 106 87 84 97 63 115 50 141 50 165 60 225 150 285 165 285 225 285 225 15 180 15
Circle -16777216 true false 180 30 90
Circle -16777216 true false 180 180 90
Polygon -16777216 true false 80 138 78 168 135 166 135 91 105 106 96 111 89 120
Circle -7500403 true true 195 195 58
Circle -7500403 true true 195 47 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
