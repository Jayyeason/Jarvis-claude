from __future__ import annotations

from typing import Literal, Optional

from pydantic import BaseModel, Field


class StoredAPIKey(BaseModel):
    id: str
    masked_key: str
    created_at: Optional[str] = None


class ProviderConfig(BaseModel):
    model_id: Optional[str] = None
    base_url: Optional[str] = None
    configured: bool
    api_keys: Optional[list[StoredAPIKey]] = None
    active_api_key_id: Optional[str] = None


class GatewayConfig(BaseModel):
    active_provider_id: Optional[str] = None
    active_model_id: Optional[str] = None
    active_model_vision: bool
    providers: dict[str, ProviderConfig]


class SettingsRequest(BaseModel):
    provider_id: str
    model_id: str
    api_key: str = ""
    api_key_id: Optional[str] = None
    base_url: Optional[str] = None
    aws_access_key: Optional[str] = None
    aws_secret_key: Optional[str] = None
    region: Optional[str] = None


class VerifyRequest(BaseModel):
    provider_id: str
    api_key: str = ""
    api_key_id: Optional[str] = None
    base_url: Optional[str] = None
    model_id: str = ""
    aws_access_key: Optional[str] = None
    aws_secret_key: Optional[str] = None
    region: Optional[str] = None


class VerifyResponse(BaseModel):
    status: Optional[str] = None
    models: Optional[list[str]] = None
    detail: Optional[str] = None


class ModelSource(BaseModel):
    source: Literal["cloud", "local"]
    provider_id: Optional[str] = None
    model_id: str
    repo_id: Optional[str] = None
    display_name: str
    provider_display_name: Optional[str] = None
    supports_vision: Optional[bool] = None
    configured: Optional[bool] = None
    loaded: Optional[bool] = None


class GatewayDetailResponse(BaseModel):
    status: Optional[str] = None
    detail: Optional[str] = None
    active: Optional[ModelSource] = None
    provider: Optional[str] = None
    model: Optional[str] = None
    active_api_key_id: Optional[str] = None


class AvailableModelsResponse(BaseModel):
    active: Optional[ModelSource] = None
    sources: list[ModelSource]
    mlx_available: bool
    models_dir: str


class ActivateModelRequest(BaseModel):
    source: Literal["cloud", "local"]
    model_id: str
    provider_id: Optional[str] = None


class LocalModelManifest(BaseModel):
    id: str
    kind: Optional[str] = None
    engine: Optional[str] = None
    repo_id: str
    display_name: str
    revision: Optional[str] = None
    supports_vision: Optional[bool] = None
    installed_at: Optional[str] = None
    local_path: str


class RecommendedLocalModel(BaseModel):
    repo_id: str
    display_name: str
    notes: Optional[str] = None


class ModelDownloadStatus(BaseModel):
    model_id: str
    repo_id: str
    display_name: Optional[str] = None
    revision: Optional[str] = None
    status: str
    error: Optional[str] = None
    local_path: Optional[str] = None


class ModelDownloadStatusResponse(BaseModel):
    downloads: list[ModelDownloadStatus]


class LocalModelsResponse(BaseModel):
    models_dir: str
    installed: list[LocalModelManifest]
    recommended: list[RecommendedLocalModel]
    active_provider_id: Optional[str] = None
    active_model_id: Optional[str] = None
    mlx_available: bool
    huggingface_hub_available: bool
    downloads: list[ModelDownloadStatus]


class ModelDownloadRequest(BaseModel):
    repo_id: str
    display_name: Optional[str] = None
    revision: Optional[str] = None


class ModelActionRequest(BaseModel):
    model_id: str


class RecurrencePayload(BaseModel):
    frequency: Literal["daily", "weekly", "monthly", "yearly"]
    interval: int = 1
    weekdays: Optional[list[Literal[
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
    ]]] = None
    end_date: Optional[str] = None
    occurrence_count: Optional[int] = None


class CalendarPayload(BaseModel):
    title: Optional[str] = None
    notes: Optional[str] = None
    location: Optional[str] = None
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    is_all_day: bool = False
    needs_duration: bool = False
    recurrence: Optional[RecurrencePayload] = None
    travel_time_minutes: Optional[int] = None
    alert_minutes_before_start: int = 10
    calendar_name: Optional[str] = None
    url: Optional[str] = None


class ReminderPayload(BaseModel):
    title: Optional[str] = None
    notes: Optional[str] = None
    location: Optional[str] = None
    due_date: Optional[str] = None
    due_time: Optional[str] = None
    recurrence: Optional[RecurrencePayload] = None
    alert_minutes_before_due: Optional[int] = None
    list_name: str = "提醒事项"
    priority: Literal["none", "low", "medium", "high"] = "none"
    flagged: bool = False
    url: Optional[str] = None


class ConflictInfo(BaseModel):
    id: str
    title: str
    start_time: str
    end_time: str
    calendar_name: Optional[str] = None


class RecognitionCandidate(BaseModel):
    id: str
    kind: Literal["calendar", "reminder"]
    calendar: Optional[CalendarPayload] = None
    reminder: Optional[ReminderPayload] = None
    confidence: float = Field(default=0.8, ge=0, le=1)
    evidence: Optional[str] = None
    missing_fields: list[str] = Field(default_factory=list)
    clarification_question: Optional[str] = None
    conflicts: list[ConflictInfo] = Field(default_factory=list)
    status: Literal["ready", "needs_input", "conflict", "skipped", "written", "error"] = "ready"


class ChatRequest(BaseModel):
    message: str = ""
    image: Optional[str] = None
    input_mode: Literal["vision", "ocr_text", "user_text"] = "user_text"
    session_id: Optional[str] = None
    form_data: Optional[dict[str, str]] = None
    user_action: Optional[Literal["accepted", "modified", "rejected"]] = None
    original_result: Optional[dict[str, str]] = None
    corrections: Optional[dict[str, str]] = None
    selected_candidate_ids: Optional[list[str]] = None


class AgentResponse(BaseModel):
    type: Literal["batch", "clarification", "none", "error"]
    session_id: Optional[str] = None
    candidates: list[RecognitionCandidate] = Field(default_factory=list)
    reply: Optional[str] = None
    error: Optional[str] = None
    missing_fields: list[str] = Field(default_factory=list)
    prefilled: Optional[dict[str, str]] = None


class CalendarEventSnapshot(BaseModel):
    id: str
    title: str
    start_time: str
    end_time: str
    is_all_day: bool = False
    location: Optional[str] = None


class ReminderSnapshot(BaseModel):
    id: str
    title: str
    due_time: Optional[str] = None
    is_completed: bool = False
    priority: int = 0


class HeartbeatTickRequest(BaseModel):
    now: str
    app_active: bool
    today_events: list[CalendarEventSnapshot] = Field(default_factory=list)
    tomorrow_events: list[CalendarEventSnapshot] = Field(default_factory=list)
    incomplete_reminders: list[ReminderSnapshot] = Field(default_factory=list)


class ProactiveEvent(BaseModel):
    id: str
    trigger_type: str
    title: str
    body: str
    primary_button: Optional[str] = None
    snooze_options: list[int] = Field(default_factory=lambda: [15, 30, 60])


class HeartbeatTickResponse(BaseModel):
    events: list[ProactiveEvent] = Field(default_factory=list)


class MemoryStatus(BaseModel):
    directory: str
    files: dict[str, bool]
    prompt_context: str
    recent_learnings: str = ""
    recent_errors: str = ""


class MemoryFeedbackRequest(BaseModel):
    action: Literal["accepted", "modified", "rejected", "skipped", "written"]
    candidate_id: Optional[str] = None
    candidate_kind: Optional[Literal["calendar", "reminder"]] = None
    title: Optional[str] = None
    status: Optional[str] = None
    modified: bool = False
    note: Optional[str] = None


class MemoryFeedbackResponse(BaseModel):
    status: str


CONTRACT_MODELS = [
    StoredAPIKey,
    ProviderConfig,
    GatewayConfig,
    SettingsRequest,
    VerifyRequest,
    VerifyResponse,
    ModelSource,
    GatewayDetailResponse,
    AvailableModelsResponse,
    ActivateModelRequest,
    LocalModelManifest,
    RecommendedLocalModel,
    ModelDownloadStatus,
    ModelDownloadStatusResponse,
    LocalModelsResponse,
    ModelDownloadRequest,
    ModelActionRequest,
    RecurrencePayload,
    CalendarPayload,
    ReminderPayload,
    ConflictInfo,
    RecognitionCandidate,
    ChatRequest,
    AgentResponse,
    CalendarEventSnapshot,
    ReminderSnapshot,
    HeartbeatTickRequest,
    ProactiveEvent,
    HeartbeatTickResponse,
    MemoryStatus,
    MemoryFeedbackRequest,
    MemoryFeedbackResponse,
]
