extends Node

var GA = load("res://analytics/analytics.gd").new()
var Save = load("res://BasicSave.gd").new()

var _game_timer = 0
var _event_timer = 0
var _event_delay = 20

func _ready():
	# this allows the library to auto quit
	add_child(GA)
	
	# always have to initialize the library
	var saved_data = Save.init()
	
	# add your keys here
	#GA.game_key = ''
	#GA.secret_key = ''
	
	# these are required fields.
	# I added basic save functionality to this project to show how this should work—you should generate a user id the first time the run the game, and save that data
	# Same with the session_num. Set it to 0 on first run, and just increment it every time afterwards
	GA.set_key('user_id', saved_data.user_id)
	GA.set_key('game_version', '0.0.1')
	GA.set_key('session_num', saved_data.session_num)
	
	GA.request_init()
	GA.add_to_event_queue(GA.get_design_event("GameEvent:start_game", 0))
	
	# turning off auto quit, so we can send final events
	get_tree().set_auto_accept_quit(false)


func _process(delta):
	# game timer is tracked for the end game event
	_game_timer += delta
	# event timer is a repeating timer that submits all pending events after counting down
	_event_timer -= delta
	# this has to be called every frame. This allows the GA library to remain asynchronous
	GA.process(delta)
	
	# we submit events only at the end of this timer. You can make the timer whatever length you like, 20 seconds seems to work well for a default
	if _event_timer <= 0:
		GA.submit_events()
		_event_timer = _event_delay


func _notification(what):
	# overwriting the default quit behavior, in order to submit final events
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		GA.add_to_event_queue(GA.get_session_end_event(int(_game_timer)))
		GA.game_end = true
		GA.submit_events()