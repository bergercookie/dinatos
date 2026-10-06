from dinatos_backend.services.personas import classify_set


def test_explosive_cardio_is_explosive_not_endurance() -> None:
    sprint = {"name": "Hill Sprint", "equipment": None}
    assert classify_set(sprint, {"distance_km": 0.1}) == ("explosive", 1)
    assert classify_set(sprint, {"duration_seconds": 10}) == ("explosive", 1)


def test_a_bodyweight_hold_is_skill_and_a_run_is_endurance() -> None:
    plank = {"name": "Plank", "equipment": "body_only"}
    run = {"name": "Run", "equipment": None}
    assert classify_set(plank, {"duration_seconds": 60}) == ("bodyweight_skill", 1)
    assert classify_set(run, {"duration_seconds": 1800}) == ("endurance", 10.0)
    assert classify_set(run, {"distance_km": 5}) == ("endurance", 10.0)
    assert classify_set(run, {}) is None


def test_reps_alone_split_between_skill_and_endurance() -> None:
    assert classify_set(None, {"reps": 10}) == ("bodyweight_skill", 1)
    assert classify_set(None, {"reps": 50}) == ("endurance", 1)
    assert classify_set({"name": "Box Jump"}, {"reps": 10}) == ("explosive", 1)
    assert classify_set({"name": "Box Jump"}, {"weight_kg": 10, "reps": 5}) == ("explosive", 1)
