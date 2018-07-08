extends Node

var save_file = "user://save_game.save"
var saved_data = {}
const UUID = preload("res://analytics/uuid.gd")


func init():
	load_game()
	saved_data.session_num += 1
	
	save_game()
	print(saved_data)
	return saved_data

func save_data():
	var save_dict = {
		"user_id": get_user_id(),
		"game_version": "0.0.2",
		"session_num": get_session_num()
	}
	return save_dict


func save_game():
	var save_data = save_data()
	var save_game = File.new()
	save_game.open(save_file, File.WRITE)
	
	save_game.store_line(to_json(save_data))
	save_game.close()


func load_game():
	var save_game = File.new()
	if not save_game.file_exists(save_file):
		saved_data = save_data()
		return
	
	save_game.open(save_file, File.READ)
	saved_data = parse_json(save_game.get_as_text())
	save_game.close()
	
	var new_info = save_data()
	for d in new_info:
		if not saved_data.has(d):
			saved_data[d] = new_info[d]



func get_session_num():
	if saved_data.has('session_num'):
		return saved_data.session_num
	
	return 0

func get_user_id():
	if saved_data.has('user_id'):
		return saved_data.user_id
	
	return UUID.v4()