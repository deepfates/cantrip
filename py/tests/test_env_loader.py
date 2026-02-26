from __future__ import annotations

import os

from cantrip.env import load_dotenv_if_present


def test_load_dotenv_if_present_loads_values(tmp_path) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text(
        "\n".join(
            [
                "# comment",
                "CANTRIP_A=one",
                "CANTRIP_B='two words'",
                'CANTRIP_C="three words"',
                "",
            ]
        )
    )
    os.environ.pop("CANTRIP_A", None)
    os.environ.pop("CANTRIP_B", None)
    os.environ.pop("CANTRIP_C", None)

    loaded = load_dotenv_if_present(str(env_file))
    assert loaded is True
    assert os.environ["CANTRIP_A"] == "one"
    assert os.environ["CANTRIP_B"] == "two words"
    assert os.environ["CANTRIP_C"] == "three words"


def test_load_dotenv_if_present_respects_override_flag(tmp_path) -> None:
    env_file = tmp_path / ".env"
    env_file.write_text("CANTRIP_OVERRIDE=from_file\n")
    os.environ["CANTRIP_OVERRIDE"] = "from_env"

    load_dotenv_if_present(str(env_file), override=False)
    assert os.environ["CANTRIP_OVERRIDE"] == "from_env"

    load_dotenv_if_present(str(env_file), override=True)
    assert os.environ["CANTRIP_OVERRIDE"] == "from_file"
