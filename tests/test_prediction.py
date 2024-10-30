def test_initial_mock_values(asset):
    assert asset.name() == "Wrapped ETH"


def test_prediction_initial_Values(asset, oracle, prediction):
    assert asset.address == prediction.asset()
    assert oracle.address == prediction.oracle()
