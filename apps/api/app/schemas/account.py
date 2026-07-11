from __future__ import annotations

from typing import Literal

from pydantic import BaseModel


class AccountDeletionRequest(BaseModel):
    confirmation: Literal["delete-my-account"]
