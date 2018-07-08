extends Node
# GameAnalytics <https://gameanalytics.com/> native GDScript REST API implementation
# Cross-platform. Should work in every platform supported by Godot
# Adapted from Godot-GameAnalytics script by Montecri on GitHub — https://github.com/Montecri/Godot-GameAnalytics

""" Procedure -->

1. make an init call
	- check if game is disabled
	- calculate client timestamp offset from server time
2. start a session
3. add any custom events that you need
4. submit events in queue
5. when game ends, add session_end event to queue
6. submit events in queue
"""

""" Short list of things still needed -->
• Need to check if game is disabled in `init`
• Need to find a way to get OS version
• It would be nice if we could get the godot engine version, rather than hardcoding it
• Need to add gziping
• Need to clean up the connection code
• Need to test and cleanup on more platforms (so far tested on Mac and HTML5)
• Need to implement 'business' and 'user' events
"""

# From https://github.com/xsellier/godot-uuid
const UUID = preload("res://analytics/uuid.gd")
const DEBUG = true

var uuid = UUID.v4()

# GameAnalytics is picky about platform, so we have to modify this a lot
var platform = OS.get_name().to_lower()
# Couldn't find a way to get OS version yet. Need to adapt for iOS or anything else
var os_version = "android 4.4.4"
var sdk_version = 'rest api v2'
var device = OS.get_model_name().to_lower()
var manufacturer = OS.get_name().to_lower()

# game information
var build_version = 'alpha 0.0.1'
var engine_version = 'godot 3.0.2'

# sandbox game keys
var game_key = "5c6bcb5402204249437fb5a7a80a4959"
var secret_key = "16813a12f718bc5c620f56944e1abc3ea13ccbac"

# sandbox API urls
var base_url = "http://sandbox-api.gameanalytics.com"
var url_init = "/v2/" + game_key + "/init"
var url_events = "/v2/" + game_key + "/events"

# settings
var use_gzip = false

# private variables
var _event_delay = 1
var _event_timer = 0

# global state to track changes when code is running
var state_config = {
	# the amount of seconds the client time is offset by server_time
	# will be set when init call receives server_time
	'client_ts_offset': 0,
	# will be updated when a new session is started
	'session_id': uuid,
	# should be updated and stored every time the game is run
	'session_num': 1,
	# set if SDK is disabled or not - default enabled
	'enabled': true,
	# event queue - contains a list of event dictionaries to be JSON encoded
	'event_queue': [],
	# unique id for the user. Should be generated first time the game is run, and saved for future use
	'user_id': '',
	# optional game version
	'game_version': ''
}
var connect_info = {
	'connecting': false,
	'url': '',
	'headers': [],
	'json': ''
}
var game_end = false
var requests = HTTPClient.new()

func prepare():
	if DEBUG:
		print('device: ', device)
		print('manufacturer: ', manufacturer)
		print('platform: ', platform)
		print('os_version: ', os_version)
	
	# GameAnalytics has very specific terms that it expects for the platform
	if platform == "html5":
		platform = "webplayer"
	if platform == "osx":
		platform = "mac_osx"

	if os_version == "Windows":
		os_version = "windows 8.2"

func process(delta):
	if _event_timer > 0:
		_event_timer -= delta
	elif connect_info.connecting:
		connect()

# adding an event to the queue for later submit
func add_to_event_queue(event_dict):
	# load saved events, if any
	var f = File.new()
	if f.file_exists("user://event_queue"):
		f.open("user://event_queue", File.READ)
		state_config['event_queue'] = f.get_var()
		f.close()
	
	state_config['event_queue'].append(event_dict)
	
	# save to file
	f.open("user://event_queue", File.WRITE)
	f.store_var(state_config['event_queue'])
	f.close()


func connect():
	var status = requests.get_status()
	if _event_timer <= 0:
		if status == HTTPClient.STATUS_DISCONNECTED:
			var err = requests.connect_to_host(base_url, 80)
		elif status == HTTPClient.STATUS_CONNECTING or status == HTTPClient.STATUS_RESOLVING:
			requests.poll()
			print('Connecting')
			_event_timer = _event_delay
		elif status == HTTPClient.STATUS_CONNECTED:
			requests.request(HTTPClient.METHOD_POST, connect_info.url, connect_info.headers, connect_info.json)
		elif status == HTTPClient.STATUS_REQUESTING:
			requests.poll()
			print("Requesting...")
			_event_timer = _event_delay
		else:
			call(connect_info.callback)
			connect_info.connecting = false

func set_key(key, value):
	state_config[key] = value

# requesting init URL and returning result
func request_init():
	prepare()
		# Get version number on Android. Need something similar for iOS
	if platform == "android":
		var output = []
		var pid = OS.execute("getprop", ["ro.build.version.release"], true, output)
		# Trimming new line char at the end
		output[0] = output[0].substr(0, output[0].length() - 1)
		os_version = platform + " " + output[0]

	var init_payload = {
		'platform': platform,
		'os_version': os_version,
		'sdk_version': sdk_version
	}
	
	# generate session id
	generate_new_session_id()
	
	# Refreshing url_init since game key might have been changed externally
	url_init = "/v2/" + game_key + "/init"
	var init_payload_json = to_json(init_payload)

	var headers = [
		"Authorization: " + Marshalls.raw_to_base64(hmac_sha256(init_payload_json, secret_key)),
		"Content-Type: application/json"]
	print(Marshalls.raw_to_base64(hmac_sha256(init_payload_json, secret_key)))
	
	var response_dict
	var status_code
	
	if DEBUG:
		print(base_url)
		print(url_init)
		print(init_payload_json)
		print(Marshalls.raw_to_base64(hmac_sha256(init_payload_json, secret_key)))
		
	
	connect_info = {
		'connecting': true,
		'url': url_init,
		'headers': headers,
		'json': init_payload_json,
		'callback': 'init_callback'
	}
	
	
func init_callback():
	var text
	if requests.has_response():
		# If there is a response..
		var headers = requests.get_response_headers_as_dictionary() # Get response headers
		print("code: ", requests.get_response_code()) # Show response code
		print("**headers:\\n", headers) # Show headers

		# Getting the HTTP Body

		if requests.is_response_chunked():
			# Does it use chunks?
			print("Response is Chunked!")
		else:
			# Or just plain Content-Length
			var bl = requests.get_response_body_length()
			print("Response Length: ",bl)

		# This method works for both anyway

		var rb = PoolByteArray() # Array that will hold the data

		while requests.get_status() == HTTPClient.STATUS_BODY:
			# While there is body left to be read
			requests.poll()
			var chunk = requests.read_response_body_chunk() # Get a chunk
			if chunk.size() == 0:
				# Got nothing, wait for buffers to fill a bit
				OS.delay_usec(1000)
			else:
				rb = rb + chunk # Append to read buffer

		# Done!

		print("bytes got: ", rb.size())
		text = rb.get_string_from_ascii()
		print("Text: ", text)
		
	var status_code = requests.get_response_code()
	var response_dict = to_json(text)

	var response_string = (status_code)

	if status_code == 401:
		post_to_log("Submit events failed due to UNAUTHORIZED.")
		post_to_log("Please verify your Authorization code is working correctly and that your are using valid game keys.")

	if status_code != 200:
		post_to_log("Init request did not return 200!")
		post_to_log(response_string)

	return status_code


# submitting all events that are in the queue to the events URL
func submit_events():
	# Refreshing url_events since game key might have been changed externally
	url_events = "/v2/" + game_key + "/events"
	var event_list_json = to_json(state_config['event_queue'])
	print('submitting events')
	print(event_list_json)

	# create headers with authentication hash
	var headers = [
		"Authorization: " +  Marshalls.raw_to_base64(hmac_sha256(event_list_json, secret_key)),
		"Content-Type: application/json"]

	connect_info = {
		'connecting': true,
		'url': url_events,
		'headers': headers,
		'json': event_list_json,
		'callback': 'submit_callback'
	}


func submit_callback():
	var text
	if requests.has_response():
		# If there is a response..
		var headers = requests.get_response_headers_as_dictionary() # Get response headers
		print("code: ", requests.get_response_code()) # Show response code
		print("**headers:\\n", headers) # Show headers

		# Getting the HTTP Body

		if requests.is_response_chunked():
			# Does it use chunks?
			print("Response is Chunked!")
		else:
			# Or just plain Content-Length
			var bl = requests.get_response_body_length()
			print("Response Length: ",bl)

		# This method works for both anyway

		var rb = PoolByteArray() # Array that will hold the data

		while requests.get_status() == HTTPClient.STATUS_BODY:
			# While there is body left to be read
			requests.poll()
			var chunk = requests.read_response_body_chunk() # Get a chunk
			if chunk.size() == 0:
				# Got nothing, wait for buffers to fill a bit
				OS.delay_usec(1000)
			else:
				rb = rb + chunk # Append to read buffer

		# Done!

		print("bytes got: ", rb.size())
		text = rb.get_string_from_ascii()
		print("Text: ", text)

	var status_code = requests.get_response_code()

	# check response code
	var status_code_string = str(status_code)
	if status_code == 400:
		post_to_log(status_code_string)
		post_to_log("Submit events failed due to BAD_REQUEST.")
		# If bad request, then some parameter is very wrong. Eliminating queue in order to no hold submission
		# In future instances where the bad parameter is no longer existing
		state_config['event_queue'] = []
		var dir = Directory.new()
		dir.remove("user://event_queue")

	elif status_code != 200:
		post_to_log(status_code_string)
		post_to_log("Submit events request did not succeed! Perhaps offline.. ")

	if status_code == 200:
		post_to_log("Events submitted !")
		# clear event queue
		# If submitte successfully, then clear queue and remove queu file to not create duplicate entries
		state_config['event_queue'] = []
		var dir = Directory.new()
		dir.remove("user://event_queue")

	else:
		post_to_log("Event submission FAILED!")

	if game_end and get_tree():
		get_tree().quit()
	return status_code


# ------------------ HELPER METHODS ---------------------- #


func generate_new_session_id():
	state_config['session_id'] = uuid
	print_verbose("Session Id: " + state_config['session_id'])


func update_client_ts_offset(server_ts):
	# calculate client_ts using offset from server time
	var now_ts = OS.get_unix_time_from_datetime(OS.get_datetime())
	
	var client_ts = now_ts
	var offset = client_ts - server_ts

	# if too small difference then ignore
	if offset < 10:
		state_config['client_ts_offset'] = 0
	else:
		state_config['client_ts_offset'] = offset
	print_verbose('Client TS offset calculated to: ' + str(offset))


func get_business_event_dict():
	var event_dict = {
		'category': 'business',
		'amount': 999,
		'currency': 'USD',
		'event_id': 'Weapon:SwordOfFire',  # item_type:item_id
		'cart_type': 'MainMenuShop',
		'transaction_num': 1,  # should be incremented and stored in local db
		'receipt_info': {'receipt': 'xyz', 'store': 'apple'}  # receipt is base64 encoded receipt
	}
	return 'not implemented'


func get_user_event():
	var event_dict = {
		'category': 'user'
	}
	return 'not implemented'


func get_session_end_event(length_in_seconds):
	var event_dict = {
		'category': 'session_end',
		'length': length_in_seconds
	}
	merge_dir(event_dict, annotate_event_with_default_values())
	return event_dict

func get_progression_event(event_id, score=null, attempt_num=null):
	var event_dict = {
		'event_id': event_id, # "^(Start|Fail|Complete):[A-Za-z0-9\\s\\-_\\.\\(\\)\\!\\?]{1,64}(:[A-Za-z0-9\\s\\-_\\.\\(\\)\\!\\?]{1,64}){0,2}$"
		'category': 'progression'
	}
	if score != null:
		event_dict.score = score
	if attempt_num != null:
		event_dict.attempt_num = attempt_num
	merge_dir(event_dict, annotate_event_with_default_values())
	return event_dict


func get_resource_event(event_id, amount):
	var event_dict = {
		'category': 'resource',
		'event_id': event_id, # "^(Sink|Source):[A-Za-z]{1,64}:[A-Za-z0-9\\s\\-_\\.\\(\\)\\!\\?]{1,64}:[A-Za-z0-9\\s\\-_\\.\\(\\)\\!\\?]{1,64}$"
		'amount': amount
	}
	merge_dir(event_dict, annotate_event_with_default_values())
	return event_dict

func get_design_event(event_id, value):
	var event_dict = {
		'category': 'design',
		'event_id': event_id,
		'value': value
	}
	merge_dir(event_dict, annotate_event_with_default_values())
	
	return event_dict
	
static func merge_dir(target, patch):
    for key in patch:
        target[key] = patch[key]


func get_gzip_string(string_for_gzip):
    var f = File.new()

    f.open_compressed("user://gzip", File.WRITE, File.COMPRESSION_GZIP)
    f.store_string(string_for_gzip)
    f.close()

    f.open("user://gzip", File.READ)
    var enc_text = f.get_as_text()
    f.close()
    return enc_text
    pass


# add default annotations (will alter the dict by reference)
#func annotate_event_with_default_values(event_dict):
func annotate_event_with_default_values():
	var now_ts = OS.get_datetime()
	var client_ts = OS.get_unix_time_from_datetime(OS.get_datetime())

	# TEST IDFA / IDFV
	#var idfa = 'AEBE52E7-03EE-455A-B3C4-E57283966239'
	var idfa = OS.get_unique_id().to_lower()
	var idfv = 'AEBE52E7-03EE-455A-B3C4-E57283966239'

	var default_annotations = {
		'v': 2,                                     # (required: Yes)
		'user_id': state_config.user_id,             # (required: Yes)
		#'ios_idfa': idfa,                           # (required: No - required on iOS)
		#'ios_idfv': idfv,                           # (required: No - send if found)
		# 'google_aid'                              # (required: No - required on Android)
		# 'android_id',                             # (required: No - send if set)
		# 'googleplus_id',                          # (required: No - send if set)
		# 'facebook_id',                            # (required: No - send if set)
		# 'limit_ad_tracking',                      # (required: No - send if true)
		# 'logon_gamecenter',                       # (required: No - send if true)
		# 'logon_googleplay                         # (required: No - send if true)
		#'gender': 'male',                           # (required: No - send if set)
		# 'birth_year                               # (required: No - send if set)
		# 'progression                              # (required: No - send if a progression attempt is in progress)
		#'custom_01                                 # (required: No - send if set)
		# 'custom_02                                # (required: No - send if set)
		# 'custom_03                                # (required: No - send if set)
		'client_ts': client_ts,                     # (required: Yes)
		'sdk_version': sdk_version,                 # (required: Yes)
		'os_version': os_version,                   # (required: Yes)
		'manufacturer': manufacturer,                    # (required: Yes)
		'device': device,                      # (required: Yes - if not possible set "unknown")
		'platform': platform,                       # (required: Yes)
		'session_id': state_config['session_id'],   # (required: Yes)
		'build': state_config.game_version,                     # (required: No - send if set)
		'session_num': state_config.session_num,       # (required: Yes)
		#'connection_type': 'wifi',                  # (required: No - send if available)
		# 'jailbroken                               # (required: No - send if true)
		'engine_version': engine_version            # (required: No - send if set by an engine)
	}
	#event_dict.update(default_annotations)
	#state_config['event_queue'].append(default_annotations)
	return default_annotations


func post_to_log(message):
	print(message)

func print_verbose(message):
	print(message)



func hmac_sha256(message, key):
	var x = 0
	var k
	
	if key.length() <= 64:
		k = key.to_utf8()

	# Hash key if length > 64
	if key.length() > 64:
		k =  key.sha256_buffer()

	# Right zero padding if key length < 64
	while k.size() < 64:
		k.append(convert_hex_to_dec("00"))

	var i = "".to_utf8()
	var o = "".to_utf8()
	var m = message.to_utf8()
	var s = File.new()
			
	while x < 64:
		o.append(k[x] ^ 0x5c)
		i.append(k[x] ^ 0x36)
		x += 1
		
	var inner = i + m
	
	s.open("user://temp", File.WRITE)
	s.store_buffer(inner)
	s.close()
	var z = s.get_sha256("user://temp")
	
	var outer = "".to_utf8()
	
	x = 0
	while x < 64:
		outer.append(convert_hex_to_dec(z.substr(x, 2)))
		x += 2
	
	outer = o + outer
	
	s.open("user://temp", File.WRITE)
	s.store_buffer(outer)
	s.close()
	
	z = s.get_sha256("user://temp")
	
	outer = "".to_utf8()
	
	x = 0
	while x < 64:
		outer.append(convert_hex_to_dec(z.substr(x, 2)))
		x += 2
	
	var mm = outer
	return outer
	
func convert_hex_to_dec(h):
	var c = "0123456789ABCDEF"
	
	h = h.to_upper()
	
	var r = h.right(1)
	var l = h.left(1)
	
	var b0 = c.find(r)
	var b1 = c.find(l) * 16
	
	var x = b1 + b0
	return x