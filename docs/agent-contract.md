# Agent API Contract

> [CLAUDE.md](../CLAUDE.md)의 상세 레퍼런스.
> Service API가 Agent를 호출하는 **동기 REST 계약**. 초기에는 실제 LLM보다 **Mock API 우선**.
> Contract Test를 깨지 않도록 유지할 것.

---

## Process Bookmark

```http
POST /agent/bookmarks/process
```

Request:
```json
{
  "bookmarkId": 1,
  "title": "string",
  "url": "string",
  "content": "string"
}
```

Response:
```json
{
  "summary": "string",
  "interests": ["AI Agent", "LangGraph"],
  "tags": ["RAG", "Tool-use"],
  "confidence": 0.87
}
```

---

## Generate Card

```http
POST /agent/cards/generate
```

Request:
```json
{
  "userId": 1,
  "interests": ["AI Agent"],
  "bookmarks": [
    { "title": "string", "summary": "string", "url": "string" }
  ],
  "collectedItems": []
}
```

Response:
```json
{
  "cards": [
    {
      "title": "string",
      "summary": "string",
      "whyForYou": "string",
      "sources": [
        { "title": "string", "url": "string" }
      ]
    }
  ]
}
```
