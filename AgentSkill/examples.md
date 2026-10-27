# Mindscape Agent examples

## Project plan

```bash
mindscape map create "Q4 规划" --template project
# use the returned map id and root id
mindscape node add <map> --parent <root> --text "目标"
mindscape node add <map> --parent <root> --text "里程碑"
mindscape node add <map> --parent <root> --text "风险"
mindscape map export <map> --format md --out ~/Downloads/q4-plan.md
```

## Meeting notes

```http
POST /v1/maps
{"title":"周会纪要","template":"meeting"}

POST /v1/maps/<id>/batch
{"operations":[
  {"op":"addNode","parentId":"<root>","text":"结论"},
  {"op":"addNode","parentId":"<root>","text":"待办"},
  {"op":"addNode","parentId":"<todo-node>","text":"负责人 / 截止时间"}
]}
```

## Read, edit, export

```bash
mindscape map list
mindscape map show <map>
mindscape node set <map> <node> --text "更新后的标题"
mindscape map export <map> --format pdf --out ~/Desktop/plan.pdf
```

## Failure handling

- `401`: read the gateway file again; the token may have rotated.
- `403`: the app is not accepting agent requests, or the request did not come from localhost.
- `409`: cycle/self-move or deleting the last remaining node.
- `413`: split the batch or shorten the text.
- `503`: gateway stopped; ask the user to enable it and retry once.
