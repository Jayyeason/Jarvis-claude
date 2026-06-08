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


class AppliedPreference(BaseModel):
    field: str
    value: str
    label: str
    source: Literal["manual", "learned", "legacy", "default"]
    message: str


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
    applied_preferences: list[AppliedPreference] = Field(default_factory=list)


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


class AssistantChatRequest(BaseModel):
    message: str = ""
    session_id: Optional[str] = None


class AssistantDateRange(BaseModel):
    start_date: Optional[str] = None
    end_date: Optional[str] = None
    label: Optional[str] = None


class AssistantActionTarget(BaseModel):
    item_kind: Literal["calendar", "reminder", "both"] = "both"
    title_keywords: list[str] = Field(default_factory=list)
    date_range: Optional[AssistantDateRange] = None
    time_of_day: Optional[str] = None
    time_period: Optional[str] = None
    raw_text: Optional[str] = None


class AssistantOperationPatch(BaseModel):
    shift_minutes: Optional[int] = None
    alert_minutes_before: Optional[int] = None
    new_start_time: Optional[str] = None
    new_end_time: Optional[str] = None
    new_due_date: Optional[str] = None
    new_due_time: Optional[str] = None
    title: Optional[str] = None
    location: Optional[str] = None


class AssistantMemoryAction(BaseModel):
    tool: Literal[
        "set_user_profile",
        "append_user_memory",
        "update_schedule_preferences",
        "propose_soul_change",
    ]
    arguments: dict[str, str] = Field(default_factory=dict)
    confidence: float = 1.0
    requires_confirmation: bool = False


class AssistantNotePayload(BaseModel):
    title: str
    content: str


class AssistantActionPlan(BaseModel):
    action: Literal[
        "chat",
        "create_candidates",
        "create_note",
        "update_preference",
        "update_memory",
        "list_items",
        "delete_items",
        "reschedule_item",
        "update_alert",
        "clarify",
    ]
    reply: Optional[str] = None
    clarification_question: Optional[str] = None
    target: Optional[AssistantActionTarget] = None
    patch: Optional[AssistantOperationPatch] = None
    note: Optional[AssistantNotePayload] = None
    preference_values: Optional[dict[str, str]] = None
    memory_actions: list[AssistantMemoryAction] = Field(default_factory=list)
    confirmation_required: bool = True


class AgentResponse(BaseModel):
    type: Literal["batch", "clarification", "none", "error"]
    session_id: Optional[str] = None
    candidates: list[RecognitionCandidate] = Field(default_factory=list)
    reply: Optional[str] = None
    error: Optional[str] = None
    missing_fields: list[str] = Field(default_factory=list)
    prefilled: Optional[dict[str, str]] = None


class AssistantChatResponse(BaseModel):
    session_id: str
    reply: str
    action: Literal[
        "chat",
        "review_candidates",
        "execute_note",
        "preference_updated",
        "list_items",
        "confirm_operation",
        "execute_operation",
        "clarify",
        "error",
    ]
    agent_response: Optional[AgentResponse] = None
    action_plan: Optional[AssistantActionPlan] = None
    updated_preferences: Optional[dict[str, str]] = None
    memory_updates: Optional[list[dict[str, str]]] = None
    error: Optional[str] = None


class CalendarEventSnapshot(BaseModel):
    id: str
    title: str
    start_time: str
    end_time: str
    is_all_day: bool = False
    location: Optional[str] = None
    calendar_name: Optional[str] = None
    alert_minutes_before_start: Optional[int] = None


class ReminderSnapshot(BaseModel):
    id: str
    title: str
    due_date: Optional[str] = None
    due_time: Optional[str] = None
    is_completed: bool = False
    priority: int = 0
    list_name: Optional[str] = None
    alert_minutes_before_due: Optional[int] = None


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


class MemoryFile(BaseModel):
    id: str
    filename: str
    title: str
    editable: bool
    content: str = ""
    truncated: bool = False
    byte_size: int = 0


class MemoryFilesResponse(BaseModel):
    files: list[MemoryFile] = Field(default_factory=list)


class MemoryFileUpdateRequest(BaseModel):
    content: str


class MemoryFileUpdateResponse(BaseModel):
    file: MemoryFile


class PreferenceMeta(BaseModel):
    source: Optional[str] = None
    confidence: Optional[float] = None
    observations: Optional[int] = None
    updated_at: Optional[str] = None
    cleared: Optional[bool] = None


class PreferenceStatValue(BaseModel):
    count: int = 0
    sessions: list[str] = Field(default_factory=list)
    last_seen: Optional[str] = None


class MemoryPreferencesResponse(BaseModel):
    preferences: dict[str, str]
    preference_meta: dict[str, PreferenceMeta] = Field(default_factory=dict)
    preference_stats: dict[str, dict[str, PreferenceStatValue]] = Field(default_factory=dict)


class MemoryPreferencesPatch(BaseModel):
    calendar_default_duration_minutes: Optional[int] = None
    calendar_default_alert_minutes: Optional[int] = None
    reminder_default_alert_minutes: Optional[int] = None
    reminder_default_due_time: Optional[str] = None
    reminder_default_priority_for_deadline: Optional[str] = None


class MemoryFeedbackRequest(BaseModel):
    action: Literal["accepted", "modified", "rejected", "skipped", "written", "replaced"]
    session_id: Optional[str] = None
    candidate_id: Optional[str] = None
    candidate_kind: Optional[Literal["calendar", "reminder"]] = None
    title: Optional[str] = None
    status: Optional[str] = None
    modified: bool = False
    note: Optional[str] = None
    final_candidate: Optional[RecognitionCandidate] = None


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
    AppliedPreference,
    RecognitionCandidate,
    ChatRequest,
    AssistantChatRequest,
    AssistantDateRange,
    AssistantActionTarget,
    AssistantOperationPatch,
    AssistantMemoryAction,
    AssistantNotePayload,
    AssistantActionPlan,
    AgentResponse,
    AssistantChatResponse,
    CalendarEventSnapshot,
    ReminderSnapshot,
    HeartbeatTickRequest,
    ProactiveEvent,
    HeartbeatTickResponse,
    MemoryStatus,
    MemoryFile,
    MemoryFilesResponse,
    MemoryFileUpdateRequest,
    MemoryFileUpdateResponse,
    PreferenceMeta,
    PreferenceStatValue,
    MemoryPreferencesResponse,
    MemoryPreferencesPatch,
    MemoryFeedbackRequest,
    MemoryFeedbackResponse,
]
