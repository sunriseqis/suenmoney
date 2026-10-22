# 原生端接口契约（计划三 S0-1）

> **用途**：iOS / 鸿蒙两端必须实现的 24 条路径，每条附 `curl` 与**真实响应样例**。
> 样例取自 2026-10-22 的本地实例（演示账本），字段名与嵌套层级可直接照抄。

> **全局约定**
> - 认证：`POST /api/auth/login` 拿 `token`，其后所有请求带 `Authorization: Bearer <token>`
> - 金额：**整数分**（`amountCents`）；日期：`YYYY-MM-DD` 字符串
> - 报表月份归属以 **`repaymentDate`（还款日）** 为准，不是消费日
> - 删除是**墓碑**（软删除），永不物理删除
> - 列表分页用**游标**（`nextCursor`），不是 offset

### 1. POST `/api/auth/login`

登录 → 不透明会话令牌（Bearer）　实测：`200`

```bash
curl -s -X POST 'http://127.0.0.1:5310/api/auth/login' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"username":"<用户名>","password":"<口令>"}'
```

```json
{
  "token": "3OC3_1-BfGK9Z8EdgKJQUAGp9BBRqOieC7xj_uR14n8",
  "expiresAt": "2027-04-20T13:05:05.516Z",
  "user": {
    "id": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
    "username": "suen",
    "displayName": "我",
    "role": "admin"
  }
}
```

### 2. GET `/api/auth/status`

首装判断：needsSetup　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/auth/status' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "needsSetup": false
}
```

### 3. GET `/api/auth/me`

当前登录用户　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/auth/me' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "user": {
    "id": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
    "username": "suen",
    "displayName": "我",
    "role": "admin"
  }
}
```

### 4. POST `/api/auth/logout`

注销当前令牌　实测：`未执行`（会注销本次会话，不执行）

```bash
curl -s -X POST 'http://127.0.0.1:5310/api/auth/logout' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}'
```

### 5. GET `/api/categories`

分类树：一级含 children（二级继承父级颜色）　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/categories' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "categories": [
    {
      "id": "01M5E9YAC5RZE4VM35K0YTXDRK",
      "parentId": null,
      "name": "餐饮",
      "depth": 1,
      "icon": "",
      "color": "",
      "sortOrder": 0,
      "isEnabled": true,
      "expenseCount": 25,
      "children": [
        {
          "id": "01M5EV4HGWV4YFCNDD8RDMWTZH",
          "parentId": "01M5E9YAC5RZE4VM35K0YTXDRK",
          "name": "买菜",
          "depth": 2,
          "icon": "",
          "color": "",
          "sortOrder": 0,
          "isEnabled": true,
          "expenseCount": 8,
          "children": []
        },
        {
          "id": "01M5EV4HMGGHT0P48RKRK8GV00",
          "parentId": "01M5E9YAC5RZE4VM35K0YTXDRK",
          "name": "外卖",
          "depth": 2,
          "icon": "",
          "color": "",
          "sortOrder": 0,
          "isEnabled": true,
          "expenseCount": 10,
          "children": []
        },
        "…共 4 项"
      ]
    },
    {
      "id": "01M5EV4HJB8ZJVQ6NJ66ZS4GBK",
      "parentId": null,
      "name": "交通",
      "depth": 1,
      "icon": "",
      "color": "",
      "sortOrder": 0,
      "isEnabled": true,
      "expenseCount": 11,
      "children": [
        {
          "id": "01M5EV4HK3KGK3G3W3EZHRBQ85",
          "parentId": "01M5EV4HJB8ZJVQ6NJ66ZS4GBK",
          "name": "地铁",
          "depth": 2,
          "icon": "",
          "color": "",
          "sortOrder": 0,
          "isEnabled": true,
          "expenseCount": 4,
          "children": []
        },
        {
          "id": "01M5EV4HSVPB9YK5Q8NB36PR7G",
          "parentId": "01M5EV4HJB8ZJVQ6NJ66ZS4GBK",
          "name": "打车",
          "depth": 2,
          "icon": "",
          "color": "",
          "sortOrder": 0,
          "isEnabled": true,
          "expenseCount": 5,
          "children": []
        },
        "…共 4 项"
      ]
    },
    "…共 6 项"
  ]
}
```

### 6. GET `/api/payment-methods`

支付方式：type = credit | cash，credit 带账期　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/payment-methods' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "paymentMethods": [
    {
      "id": "01M5E9YFE4PBND608179W6R3NS",
      "name": "现金",
      "type": "cash",
      "icon": "",
      "billingDay": null,
      "repaymentDay": null,
      "isEnabled": true,
      "sortOrder": 0,
      "expenseCount": 15
    },
    {
      "id": "01M5EV4HDSNYD5ZC6QAT236YD2",
      "name": "招行信用卡",
      "type": "credit",
      "icon": "",
      "billingDay": 10,
      "repaymentDay": 28,
      "isEnabled": true,
      "sortOrder": 2,
      "expenseCount": 29
    },
    "…共 4 项"
  ]
}
```

### 7. GET `/api/users`

家庭成员（记录人来源）　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/users' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "users": [
    {
      "id": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
      "username": "suen",
      "displayName": "我",
      "role": "admin"
    },
    {
      "id": "01M5EV4896226TSXMQ5ZRQV785",
      "username": "lin",
      "displayName": "爱人",
      "role": "member"
    }
  ]
}
```

### 8. POST `/api/expenses/preview`

账期预览：这笔会记在哪个月　实测：`200`

```bash
curl -s -X POST 'http://127.0.0.1:5310/api/expenses/preview' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"spendDate":"2026-10-22","paymentMethodId":"01M5E9YFE4PBND608179W6R3NS"}'
```

```json
{
  "postingDate": "2026-10-22",
  "repaymentDate": "2026-10-22"
}
```

### 9. GET `/api/expenses?limit=2`

流水列表：游标分页（nextCursor / hasMore）　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/expenses?limit=2' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "items": [
    {
      "id": "01M5HVE5CJDDVF256ETA034B7X",
      "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
      "ownerName": "我",
      "amountCents": 1234,
      "categoryId": "01M5EV4HGWV4YFCNDD8RDMWTZH",
      "categoryName": "买菜",
      "categoryIcon": "",
      "categoryColor": "",
      "parentCategoryColor": "",
      "parentCategoryName": "餐饮",
      "paymentMethodId": "01M5E9YFE4PBND608179W6R3NS",
      "paymentMethodName": "现金",
      "paymentMethodType": "cash",
      "spendDate": "2026-10-22",
      "postingDate": "2026-10-22",
      "repaymentDate": "2026-10-22",
      "note": "契约文档取样（临时）",
      "source": "manual",
      "planId": null,
      "planPeriodSeq": null,
      "createdAt": "2026-10-22T13:05:05.426Z",
      "updatedAt": "2026-10-22T13:05:05.426Z"
    },
    {
      "id": "01M5EVAXZ6NY78ZE4PP5WH9WBG",
      "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
      "ownerName": "我",
      "amountCents": -9600,
      "categoryId": "01M5EV9RM6VH5Y3X1ZDHGJRTX3",
      "categoryName": "电影",
      "categoryIcon": "",
      "categoryColor": "",
      "parentCategoryColor": "",
      "parentCategoryName": "娱乐",
      "paymentMethodId": "01M5EV4HDSNYD5ZC6QAT236YD2",
      "paymentMethodName": "招行信用卡",
      "paymentMethodType": "credit",
      "spendDate": "2026-10-20",
      "postingDate": "2026-11-10",
      "repaymentDate": "2026-11-28",
      "note": "电影票退款（场次取消）",
      "source": "manual",
      "planId": null,
      "planPeriodSeq": null,
      "createdAt": "2026-10-21T09:05:32.697Z",
      "updatedAt": "2026-10-21T09:05:32.697Z"
    }
  ],
  "nextCursor": "2026-10-20|01M5EVAXZ6NY78ZE4PP5WH9WBG",
  "hasMore": true
}
```

### 10. GET `/api/expenses/01M5HVE5CJDDVF256ETA034B7X`

单笔明细　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/expenses/01M5HVE5CJDDVF256ETA034B7X' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "expense": {
    "id": "01M5HVE5CJDDVF256ETA034B7X",
    "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
    "ownerName": "我",
    "amountCents": 1234,
    "categoryId": "01M5EV4HGWV4YFCNDD8RDMWTZH",
    "categoryName": "买菜",
    "categoryIcon": "",
    "categoryColor": "",
    "parentCategoryColor": "",
    "parentCategoryName": "餐饮",
    "paymentMethodId": "01M5E9YFE4PBND608179W6R3NS",
    "paymentMethodName": "现金",
    "paymentMethodType": "cash",
    "spendDate": "2026-10-22",
    "postingDate": "2026-10-22",
    "repaymentDate": "2026-10-22",
    "note": "契约文档取样（临时）",
    "source": "manual",
    "planId": null,
    "planPeriodSeq": null,
    "createdAt": "2026-10-22T13:05:05.426Z",
    "updatedAt": "2026-10-22T13:05:05.426Z"
  }
}
```

### 11. POST `/api/expenses`

新增；amountCents 为负即退款冲销　实测：`201`

```bash
curl -s -X POST 'http://127.0.0.1:5310/api/expenses' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"amountCents":1234,"categoryId":"01M5EV4HGWV4YFCNDD8RDMWTZH","paymentMethodId":"01M5E9YFE4PBND608179W6R3NS","spendDate":"2026-10-22","note":"<备注>"}'
```

```json
{
  "expense": {
    "id": "01M5HVE5H0FWYPV03ZN869HR68",
    "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
    "ownerName": "我",
    "amountCents": 1234,
    "categoryId": "01M5EV4HGWV4YFCNDD8RDMWTZH",
    "categoryName": "买菜",
    "categoryIcon": "",
    "categoryColor": "",
    "parentCategoryColor": "",
    "parentCategoryName": "餐饮",
    "paymentMethodId": "01M5E9YFE4PBND608179W6R3NS",
    "paymentMethodName": "现金",
    "paymentMethodType": "cash",
    "spendDate": "2026-10-22",
    "postingDate": "2026-10-22",
    "repaymentDate": "2026-10-22",
    "note": "契约文档取样（临时）",
    "source": "manual",
    "planId": null,
    "planPeriodSeq": null,
    "createdAt": "2026-10-22T13:05:05.568Z",
    "updatedAt": "2026-10-22T13:05:05.568Z"
  }
}
```

### 12. PATCH `/api/expenses/01M5HVE5CJDDVF256ETA034B7X`

修改任意字段（金额/分类/支付/日期/备注）　实测：`200`

```bash
curl -s -X PATCH 'http://127.0.0.1:5310/api/expenses/01M5HVE5CJDDVF256ETA034B7X' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"amountCents":1200}'
```

```json
{
  "expense": {
    "id": "01M5HVE5CJDDVF256ETA034B7X",
    "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
    "ownerName": "我",
    "amountCents": 1200,
    "categoryId": "01M5EV4HGWV4YFCNDD8RDMWTZH",
    "categoryName": "买菜",
    "categoryIcon": "",
    "categoryColor": "",
    "parentCategoryColor": "",
    "parentCategoryName": "餐饮",
    "paymentMethodId": "01M5E9YFE4PBND608179W6R3NS",
    "paymentMethodName": "现金",
    "paymentMethodType": "cash",
    "spendDate": "2026-10-22",
    "postingDate": "2026-10-22",
    "repaymentDate": "2026-10-22",
    "note": "契约文档取样（临时）",
    "source": "manual",
    "planId": null,
    "planPeriodSeq": null,
    "createdAt": "2026-10-22T13:05:05.426Z",
    "updatedAt": "2026-10-22T13:05:05.575Z"
  }
}
```

### 13. DELETE `/api/expenses/01M5HVE5CJDDVF256ETA034B7X`

软删除（墓碑，不物理删除）　实测：`未执行`（删临时样本，执行）

```bash
curl -s -X DELETE 'http://127.0.0.1:5310/api/expenses/01M5HVE5CJDDVF256ETA034B7X' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

### 14. GET `/api/reports/monthly?month=2026-10`

月度：合计/环比/分类/支付/成员/日节奏/近12月　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/reports/monthly?month=2026-10' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "report": {
    "month": "2026-10",
    "totalCents": 203714,
    "count": 23,
    "previous": {
      "month": "2026-09",
      "totalCents": 252840
    },
    "change": {
      "deltaCents": -49126,
      "ratio": -0.194296788482835
    },
    "yearAgo": {
      "label": "10",
      "totalCents": 0,
      "change": {
        "deltaCents": 203714,
        "ratio": null
      }
    },
    "largest": {
      "expenseId": "01M5EVAXSCJNN2A2T0NZ15YVAE",
      "categoryName": "餐饮",
      "cents": 32800,
      "repaymentDate": "2026-10-28"
    },
    "categories": [
      {
        "categoryId": "01M5E9YAC5RZE4VM35K0YTXDRK",
        "name": "餐饮",
        "icon": "",
        "color": "",
        "cents": 145064,
        "count": 11,
        "ratio": 0.7120963704016415,
        "previousCents": 91400,
        "changeRatio": 0.5871334792122538,
        "children": [
          {
            "categoryId": "01M5EV4HRDYQ03VAD4P7MZMGWJ",
            "name": "下馆子",
            "icon": "",
            "color": "",
            "cents": 66800,
            "count": 3,
            "ratio": 0.4604864060001103
          },
          {
            "categoryId": "01M5EV4HGWV4YFCNDD8RDMWTZH",
            "name": "买菜",
            "icon": "",
            "color": "",
            "cents": 66014,
            "count": 5,
            "ratio": 0.45506810786963
          },
          "…共 3 项"
        ]
      },
      {
        "categoryId": "01M5EV4HV9SBB8F4QAT8QTTMR3",
        "name": "医疗",
        "icon": "",
        "color": "",
        "cents": 22650,
        "count": 2,
        "ratio": 0.11118528917992872,
        "previousCents": 15600,
        "changeRatio": 0.4519230769230769,
        "children": [
          {
            "categoryId": "01M5EV9S3QQAHE1R8Z9MDPZPN9",
            "name": "挂号",
            "icon": "",
            "color": "",
            "cents": 20000,
            "count": 1,
            "ratio": 0.8830022075055187
          },
          {
            "categoryId": "01M5EV4HW09Y91SN8BTGEMZR6N",
            "name": "药品",
            "icon": "",
            "color": "",
            "cents": 2650,
            "count": 1,
            "ratio": 0.11699779249448124
          }
        ]
      },
      "…共 5 项"
    ],
    "paymentMethods": [
      {
        "paymentMethodId": "01M5EV4HDSNYD5ZC6QAT236YD2",
        "name": "招行信用卡",
        "type": "credit",
        "cents": 138100,
        "count": 11,
        "repaymentDate": "2026-10-28"
      },
      {
        "paymentMethodId": "01M5EV4HG3CQMC863T85CZ4XJQ",
        "name": "工资卡",
        "type": "cash",
        "cents": 28000,
        "count": 2,
        "repaymentDate": "2026-10-04"
      },
      "…共 4 项"
    ],
    "members": [
      {
        "ownerId": "01M5EV4896226TSXMQ5ZRQV785",
        "name": "爱人",
        "cents": 106480,
        "count": 8
      },
      {
        "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
        "name": "我",
        "cents": 97234,
        "count": 15
      }
    ],
    "daily": [
      {
        "date": "2026-10-01",
        "day": 1,
        "cents": 0,
        "count": 0
      },
      {
        "date": "2026-10-02",
        "day": 2,
        "cents": 0,
        "count": 0
      },
      "…共 31 项"
    ],
    "rolling12Months": [
      {
        "month": "2025-11",
        "totalCents": null,
        "count": 0
      },
      {
        "month": "2025-12",
        "totalCents": null,
        "count": 0
      },
      "…共 12 项"
    ],
    "average12MonthsCents": 400720,
    "rolling3MonthsDailyAverageCents": 15619,
    "nextMonthRepayments": [
      {
        "paymentMethodId": "01M5EV4HDSNYD5ZC6QAT236YD2",
        "name": "招行信用卡",
        "type": "credit",
        "cents": 114940,
        "count": 7,
        "repaymentDate": "2026-11-28"
      },
      {
        "paymentMethodId": "01M5EV4HFCZHRPA22JVAE02WTE",
        "name": "花呗",
        "type": "credit",
        "cents": 50810,
        "count": 10,
        "repaymentDate": "2026-11-09"
      }
    ],
    "nextMonthDueTotalCents": 165750
  }
}
```

### 15. GET `/api/reports/yearly?year=2026`

年度：12 月/同比/最高月/分类　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/reports/yearly?year=2026' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "report": {
    "year": "2026",
    "totalCents": 4904394,
    "count": 75,
    "months": [
      {
        "month": "2026-01",
        "totalCents": 528000,
        "count": 1
      },
      {
        "month": "2026-02",
        "totalCents": 528000,
        "count": 1
      },
      "…共 12 项"
    ],
    "yearAgo": {
      "label": "去年",
      "totalCents": 0,
      "change": {
        "deltaCents": 4904394,
        "ratio": null
      }
    },
    "largest": {
      "expenseId": "01M5EVAVHCDDW2KNSTJC3XHJ5J",
      "categoryName": "居住",
      "cents": 528000,
      "repaymentDate": "2026-01-20"
    },
    "categories": [
      {
        "categoryId": "01M5EV4J2RRF3CDWQ06WTAJ141",
        "name": "居住",
        "icon": "",
        "color": "",
        "cents": 4264300,
        "count": 10,
        "ratio": 0.8694856082117383,
        "previousCents": 0,
        "changeRatio": null,
        "children": [
          {
            "categoryId": "01M5EV4JTSHQ60F8WXHCWHGR3F",
            "name": "房贷",
            "icon": "",
            "color": "",
            "cents": 4224000,
            "count": 8,
            "ratio": 0.9905494453954928
          },
          {
            "categoryId": "01M5EV4J3PEGQYG5TSG8BHPNBW",
            "name": "水电燃气",
            "icon": "",
            "color": "",
            "cents": 40300,
            "count": 2,
            "ratio": 0.009450554604507187
          }
        ]
      },
      {
        "categoryId": "01M5E9YAC5RZE4VM35K0YTXDRK",
        "name": "餐饮",
        "icon": "",
        "color": "",
        "cents": 304064,
        "count": 26,
        "ratio": 0.0619982815410018,
        "previousCents": 0,
        "changeRatio": null,
        "children": [
          {
            "categoryId": "01M5EV4HGWV4YFCNDD8RDMWTZH",
            "name": "买菜",
            "icon": "",
            "color": "",
            "cents": 138904,
            "count": 9,
            "ratio": 0.45682487897284785
          },
          {
            "categoryId": "01M5EV4HRDYQ03VAD4P7MZMGWJ",
            "name": "下馆子",
            "icon": "",
            "color": "",
            "cents": 118100,
            "count": 5,
            "ratio": 0.3884050726162913
          },
          "…共 4 项"
        ]
      },
      "…共 6 项"
    ],
    "members": [
      {
        "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
        "name": "我",
        "cents": 4532724,
        "count": 45
      },
      {
        "ownerId": "01M5EV4896226TSXMQ5ZRQV785",
        "name": "爱人",
        "cents": 371670,
        "count": 30
      }
    ],
    "average3YearsCents": 1634798,
    "peakMonth": {
      "month": "2026-08",
      "totalCents": 656090
    }
  }
}
```

### 16. GET `/api/reports/summary`

汇总：历史累计/记录跨度/月均/分类/成员　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/reports/summary' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "report": {
    "totalCents": 4904394,
    "count": 75,
    "firstRepaymentDate": "2026-01-20",
    "lastRepaymentDate": "2026-11-28",
    "recordedDays": 313,
    "monthlyAverageCents": 445854,
    "dailyAverageCents": 15669,
    "perExpenseAverageCents": 65392,
    "peakMonth": {
      "month": "2026-08",
      "totalCents": 656090
    },
    "years": [
      {
        "year": "2026",
        "totalCents": 4904394,
        "count": 75
      }
    ],
    "categories": [
      {
        "categoryId": "01M5EV4J2RRF3CDWQ06WTAJ141",
        "name": "居住",
        "icon": "",
        "color": "",
        "cents": 4264300,
        "count": 10,
        "ratio": 0.8694856082117383,
        "previousCents": 0,
        "changeRatio": null,
        "children": [
          {
            "categoryId": "01M5EV4JTSHQ60F8WXHCWHGR3F",
            "name": "房贷",
            "icon": "",
            "color": "",
            "cents": 4224000,
            "count": 8,
            "ratio": 0.9905494453954928
          },
          {
            "categoryId": "01M5EV4J3PEGQYG5TSG8BHPNBW",
            "name": "水电燃气",
            "icon": "",
            "color": "",
            "cents": 40300,
            "count": 2,
            "ratio": 0.009450554604507187
          }
        ]
      },
      {
        "categoryId": "01M5E9YAC5RZE4VM35K0YTXDRK",
        "name": "餐饮",
        "icon": "",
        "color": "",
        "cents": 304064,
        "count": 26,
        "ratio": 0.0619982815410018,
        "previousCents": 0,
        "changeRatio": null,
        "children": [
          {
            "categoryId": "01M5EV4HGWV4YFCNDD8RDMWTZH",
            "name": "买菜",
            "icon": "",
            "color": "",
            "cents": 138904,
            "count": 9,
            "ratio": 0.45682487897284785
          },
          {
            "categoryId": "01M5EV4HRDYQ03VAD4P7MZMGWJ",
            "name": "下馆子",
            "icon": "",
            "color": "",
            "cents": 118100,
            "count": 5,
            "ratio": 0.3884050726162913
          },
          "…共 4 项"
        ]
      },
      "…共 6 项"
    ],
    "members": [
      {
        "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
        "name": "我",
        "cents": 4532724,
        "count": 45
      },
      {
        "ownerId": "01M5EV4896226TSXMQ5ZRQV785",
        "name": "爱人",
        "cents": 371670,
        "count": 30
      }
    ]
  }
}
```

### 17. GET `/api/plans`

计划列表（含 progress：已还/未还/下次还款日）　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/plans' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "plans": [
    {
      "id": "01M5EVAVFWM2N4M1HR6NG9T6X2",
      "ownerId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
      "name": "房贷",
      "categoryId": "01M5EV4JTSHQ60F8WXHCWHGR3F",
      "paymentMethodId": "01M5EV4HG3CQMC863T85CZ4XJQ",
      "amountCents": 528000,
      "totalAmountCents": null,
      "purchaseDate": null,
      "firstDueDate": "2026-01-20",
      "remindDaysBefore": 5,
      "autoPost": false,
      "source": "manual",
      "state": "active",
      "note": "等额本息，LPR 每季度复核一次",
      "progress": {
        "paidCount": 8,
        "paidCents": 4224000,
        "pendingCount": 4,
        "pendingCents": 2112000,
        "nextDueDate": "2026-09-20",
        "expectedEndDate": "2026-12-20"
      },
      "createdAt": "2026-10-21T09:05:32.697Z",
      "updatedAt": "2026-10-21T09:05:32.697Z"
    },
    {
      "id": "01M5EVAW5QEAHR1PE9F5B397E7",
      "ownerId": "01M5EV4896226TSXMQ5ZRQV785",
      "name": "京东分期 · iPhone",
      "categoryId": "01M5EV4J1AB6BERVD88N0B4H62",
      "paymentMethodId": "01M5EV4HDSNYD5ZC6QAT236YD2",
      "amountCents": 50000,
      "totalAmountCents": 600000,
      "purchaseDate": "2026-07-05",
      "firstDueDate": "2026-08-28",
      "remindDaysBefore": 3,
      "autoPost": true,
      "source": "installment",
      "state": "active",
      "note": "12 期免息",
      "progress": {
        "paidCount": 1,
        "paidCents": 50000,
        "pendingCount": 11,
        "pendingCents": 550000,
        "nextDueDate": "2026-09-28",
        "expectedEndDate": "2027-07-28"
      },
      "createdAt": "2026-10-21T09:05:32.697Z",
      "updatedAt": "2026-10-21T09:05:32.697Z"
    },
    "…共 3 项"
  ]
}
```

### 18. POST `/api/plans`

建计划（source=manual 每期金额 / installment 原价+期数）　实测：`未执行`（会真的建计划，不执行；字段清单见 docs/api.md）

```bash
curl -s -X POST 'http://127.0.0.1:5310/api/plans' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"<计划名>","categoryId":"01M5EV4HGWV4YFCNDD8RDMWTZH","paymentMethodId":"01M5E9YFE4PBND608179W6R3NS","source":"manual","amountCents":500000,"periods":12,"firstDueDate":"2026-11-28"}'
```

### 19. GET `/api/plan-todos?status=pending`

待办列表；**传 today 才会结算到期自动入账**　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/plan-todos?status=pending' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "settled": 0,
  "todos": [
    {
      "id": "01M5EVAW2VRTE0YZF4GFYQWQS6",
      "planId": "01M5EVAVFWM2N4M1HR6NG9T6X2",
      "planName": "房贷",
      "categoryId": "01M5EV4JTSHQ60F8WXHCWHGR3F",
      "paymentMethodId": "01M5EV4HG3CQMC863T85CZ4XJQ",
      "periodSeq": 9,
      "amountCents": 528000,
      "postingDate": "2026-09-20",
      "repaymentDate": "2026-09-20",
      "remindDate": "2026-09-15",
      "status": "pending",
      "postedDate": null,
      "confirmedBy": null,
      "confirmedAt": null,
      "expenseId": null,
      "holdAutoPost": true,
      "willAutoPost": false,
      "ackAt": null
    },
    {
      "id": "01M5EVAW8M51943ZQ2WQWN4MW1",
      "planId": "01M5EVAW5QEAHR1PE9F5B397E7",
      "planName": "京东分期 · iPhone",
      "categoryId": "01M5EV4J1AB6BERVD88N0B4H62",
      "paymentMethodId": "01M5EV4HDSNYD5ZC6QAT236YD2",
      "periodSeq": 2,
      "amountCents": 50000,
      "postingDate": "2026-09-10",
      "repaymentDate": "2026-09-28",
      "remindDate": "2026-09-25",
      "status": "pending",
      "postedDate": null,
      "confirmedBy": null,
      "confirmedAt": null,
      "expenseId": null,
      "holdAutoPost": true,
      "willAutoPost": false,
      "ackAt": null
    },
    "…共 24 项"
  ]
}
```

### 20. POST `/api/plan-todos/01M5EVAVGM64T4X3G3HCM7Q12A/confirm`

入账（可带 spendDate，不影响报表月份归属）　实测：`未执行`（会真的入账，不执行）

```bash
curl -s -X POST 'http://127.0.0.1:5310/api/plan-todos/01M5EVAVGM64T4X3G3HCM7Q12A/confirm' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}'
```

### 21. POST `/api/plan-todos/01M5EVAVGM64T4X3G3HCM7Q12A/skip`

忽略（**不可逆**：跳过的期次不回待办）　实测：`未执行`（会真的忽略，不执行）

```bash
curl -s -X POST 'http://127.0.0.1:5310/api/plan-todos/01M5EVAVGM64T4X3G3HCM7Q12A/skip' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{}'
```

### 22. GET `/api/sync/status`

增量游标：latestVersion（单调递增，不用时间戳）　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/sync/status' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "latestVersion": 33
}
```

### 23. POST `/api/sync/push`

推送离线队列（单事务原子提交）　实测：`未执行`（空队列探活）

```bash
curl -s -X POST 'http://127.0.0.1:5310/api/sync/push' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"ops":[]}'
```

### 24. GET `/api/sync/pull?since=0&limit=5`

拉取变更集　实测：`200`

```bash
curl -s -X GET 'http://127.0.0.1:5310/api/sync/pull?since=0&limit=5' \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json"
```

```json
{
  "changes": [
    {
      "version": 1,
      "entityType": "user",
      "entityId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
      "op": "upsert",
      "actorId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
      "payload": {
        "id": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
        "username": "suen",
        "displayName": "我",
        "role": "admin",
        "updatedAt": "2026-10-21T04:01:36.844Z",
        "deletedAt": null,
        "rev": 1
      },
      "deviceId": null,
      "createdAt": "2026-10-21T04:01:36.951Z"
    },
    {
      "version": 2,
      "entityType": "category",
      "entityId": "01M5E9YAC5RZE4VM35K0YTXDRK",
      "op": "upsert",
      "actorId": "01M5E9YA2CJPQGQ59V4ZCGVSHE",
      "payload": {
        "id": "01M5E9YAC5RZE4VM35K0YTXDRK",
        "parentId": null,
        "name": "餐饮",
        "depth": 1,
        "icon": "",
        "color": "",
        "sortOrder": 0,
        "isEnabled": true,
        "updatedAt": "2026-10-21T04:01:37.157Z",
        "deletedAt": null,
        "rev": 1
      },
      "deviceId": null,
      "createdAt": "2026-10-21T04:01:37.157Z"
    },
    "…共 5 项"
  ],
  "latestVersion": 33,
  "hasMore": true
}
```

---

**共 24 条路径**：鉴权 4 · 字典 4 · 支出 5 · 报表 3 · 计划与待办 5 · 同步 3。

写操作的请求体字段以 `docs/api.md` 为准；本文件只冻结「路径 + 鉴权 + 响应形状」。
