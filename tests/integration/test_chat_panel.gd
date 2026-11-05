extends TestCase
## Чат «Гонки» в матче: лента поверх арены, история из Net.chat_log, открытие и закрытие.


## Тесты идут внутри _initialize раннера: узел уже в дереве, но _ready дерево ещё не рассылает.
func _panel() -> ChatPanel:
	var p: ChatPanel = ChatPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	if not p.is_node_ready():
		p.call("_ready")
	return p


func test_feed_history_and_open_close() -> void:
	var saved: Array[Dictionary] = Net.chat_log.duplicate()
	Net.chat_log.clear()
	Net.call("_post_chat", "Аня", "до матча", Color.WHITE)
	var p: ChatPanel = _panel()
	var hist: VBoxContainer = p.get("_history")
	var feed: VBoxContainer = p.get("_feed")
	assert_eq(hist.get_child_count(), 1, "история из Net.chat_log")
	assert_eq(feed.get_child_count(), 0, "старые сообщения в ленту не всплывают")
	for i: int in ChatPanel.FEED_LINES + 2:
		Net.call("_post_chat", "Борис", "gg %d" % i, Color.RED)
	assert_eq(feed.get_child_count(), ChatPanel.FEED_LINES, "в ленте только последние")
	assert_eq((feed.get_child(feed.get_child_count() - 1) as Label).text, "Борис: gg %d" % (ChatPanel.FEED_LINES + 1))
	assert_eq(hist.get_child_count(), ChatPanel.FEED_LINES + 3)
	var typing: Array = []
	p.typing_changed.connect(func(on: bool) -> void: typing.append(on))
	p.open()
	assert_true(p.is_open())
	assert_true((p.get("_box") as Control).visible)
	assert_false(feed.visible)
	p.call("_on_submit", "   ")
	assert_false(p.is_open(), "Enter закрывает чат и с пустым полем")
	assert_eq(typing, [true, false])
	p.free()
	Net.chat_log = saved
