extends TestSuite
## `--unlock` (ProgressRules.open_all): every Theater movie and the sound page open, and the menu's
## modes with them.



func test_every_theater_movie_opens() -> void:
	var flow := imported_flow()
	if flow == null:
		return
	var locked := 0
	for i in flow.data.theater_movies.size():
		if flow.theater.entry_status(i) == -1:
			locked += 1
	expect(locked > 0, "a new game has locked movies")
	expect_equal(flow.theater.all_movies(), 0)
	ProgressRules.open_all(flow.progress)
	for i in flow.data.theater_movies.size():
		expect(flow.theater.entry_status(i) != -1, "movie entry %d is open" % i)
	expect_equal(flow.theater.all_movies(), 1, "DISC and SOUND are offered")
