from __future__ import annotations

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

TravelInterest = Literal[
    "localFood",
    "cafe",
    "history",
    "arts",
    "nature",
    "walk",
    "night",
    "shopping",
    "market",
    "festival",
    "handsOn",
    "photography",
]
TravelStyle = Literal[
    "famous",
    "hiddenLocal",
    "residentFavorite",
    "newPlaces",
    "revisit",
    "spontaneous",
]
FoodCuisine = Literal[
    "korean",
    "streetFood",
    "cafeDessert",
    "marketFood",
    "worldCuisine",
]
TravelCompanion = Literal[
    "solo",
    "partner",
    "friends",
    "family",
    "children",
    "senior",
    "pet",
]
TransportMode = Literal["walk", "transit", "taxi", "car", "bicycle"]
DietaryMode = Literal["vegetarian", "vegan", "halal", "kosher"]
Allergen = Literal["nuts", "shellfish", "dairy", "eggs", "gluten", "soy"]


class _PreferenceSection(BaseModel):
    model_config = ConfigDict(extra="forbid")


class TravelPreferenceSoft(_PreferenceSection):
    pace: Literal["relaxed", "balanced", "packed"] = "balanced"
    crowd_tolerance: Literal["quiet", "balanced", "popular"] = "balanced"
    walking_band: Literal["short", "medium", "long"] = "medium"
    interests: list[TravelInterest] = Field(default_factory=list, max_length=5)
    travel_styles: list[TravelStyle] = Field(default_factory=list, max_length=3)
    indoor_outdoor: Literal["indoor", "balanced", "outdoor"] = "balanced"
    weather_sensitivity: Literal["low", "medium", "high"] = "medium"
    food_cuisines: list[FoodCuisine] = Field(default_factory=list, max_length=4)
    food_adventure: Literal["familiar", "balanced", "adventurous"] = "balanced"
    companions: list[TravelCompanion] = Field(default_factory=lambda: ["solo"])
    transport_modes: list[TransportMode] = Field(default_factory=lambda: ["transit", "walk"])
    rest_frequency: Literal["low", "balanced", "frequent"] = "balanced"
    max_one_way_minutes: Literal[15, 30, 60, 90] = 30
    max_transfers: Literal[0, 1, 2, 3] = 2
    budget_band: Literal["value", "balanced", "special"] = "balanced"
    day_rhythm: Literal["morning", "daytime", "night"] = "daytime"
    exclude_closing_soon: bool = True
    docent_depth: Literal["short", "standard", "deep"] = "standard"

    @field_validator(
        "interests",
        "travel_styles",
        "food_cuisines",
        "companions",
        "transport_modes",
    )
    @classmethod
    def _must_not_repeat_values(cls, value: list[str]) -> list[str]:
        if len(value) != len(set(value)):
            raise ValueError("preference lists must not contain duplicates")
        return value


class TravelPreferenceHard(_PreferenceSection):
    dietary_modes: list[DietaryMode] = Field(default_factory=list, max_length=4)
    allergens: list[Allergen] = Field(default_factory=list, max_length=6)
    avoid_ingredients: Annotated[str, Field(max_length=120)] = ""
    avoid_stairs: bool = False
    wheelchair_access: bool = False
    stroller_access: bool = False
    verified_accessibility_only: bool = False
    max_wait_minutes: Literal[10, 20, 40, 60] = 20

    @field_validator("dietary_modes", "allergens")
    @classmethod
    def _must_not_repeat_values(cls, value: list[str]) -> list[str]:
        if len(value) != len(set(value)):
            raise ValueError("constraint lists must not contain duplicates")
        return value

    @field_validator("avoid_ingredients")
    @classmethod
    def _normalize_avoid_ingredients(cls, value: str) -> str:
        return value.strip()


class TravelPreferenceLocale(_PreferenceSection):
    docent_autoplay: bool = False
    place_name_mode: Literal["localized", "localizedWithKorean", "korean"] = "localizedWithKorean"
    narration_speed: Literal[0.8, 1.0, 1.2] = 1.0
    continue_narration: bool = True
    pronunciation_help: bool = False


class TravelPreferencesPayload(BaseModel):
    model_config = ConfigDict(extra="forbid")

    version: Literal[1] = 1
    soft: TravelPreferenceSoft = Field(default_factory=TravelPreferenceSoft)
    hard: TravelPreferenceHard = Field(default_factory=TravelPreferenceHard)
    locale: TravelPreferenceLocale = Field(default_factory=TravelPreferenceLocale)


class SaveTravelPreferencesRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    expected_revision: int = Field(ge=0)
    preferences: TravelPreferencesPayload
