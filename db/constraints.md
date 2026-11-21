# Ограничения БД FoodExpress

Схема `sakharov_food`, PostgreSQL. Первичные ключи `uuid` формируются на сервере. Основные ограничения:

| Таблица | Ограничение | Обоснование |
|---|---|---|
| client | `UNIQUE(login)`, `UNIQUE(phone_number)` | BR-2.1, BR-2.2: уникальные логин и телефон |
| client | `password NOT NULL` | BR-2.1, BR-2.3: пароль обязателен, генерация MD5 |
| address | `UNIQUE NULLS NOT DISTINCT(street,house_number,apartment_office)` | BR-3.1–3.4: один физический адрес хранится один раз |
| client_address | составной PK, два FK | BR-2.4–2.5: много адресов у клиента, запрет повторной привязки |
| restaurant | `UNIQUE(address_id)`, FK | BR-3.3–3.4: один ресторан на адрес |
| restaurant | `CHECK(work_end > work_start)` | BR-4.4: закрытие позже открытия |
| restaurant | `CHECK(rating BETWEEN 0 AND 5)` | BR-4.2 |
| courier | `UNIQUE(phone_number)` | Идентификатор телефона курьера; BR-6.1 |
| courier | `CHECK(coefficient BETWEEN 0.1 AND 0.5)` | BR-6.4 |
| courier | проверка даты увольнения и статуса | BR-6.3 |
| courier_pay | `PRIMARY KEY(year,month,courier_id)` | BR-10.3: одна выплата за месяц |
| courier_pay | `CHECK(month BETWEEN 1 AND 12)` и положительные суммы | BR-10.1, BR-10.4 |
| product | FK на категорию и ресторан | BR-5.1 |
| product | `CHECK(price>=0)` и рейтинг 0–5 | BR-5.3, BR-5.4 |
| order | FK на клиента, ресторан, курьера, адрес | BR-7.1–7.5 |
| order | составной FK `(client_id,address_id)` | BR-7.4: доставка только на адрес клиента |
| order | `CHECK(commission=round(order_amount*0.1,2))` | BR-1.4, BR-7.10 |
| order | `CHECK(total_amount=order_amount+commission)` | BR-7.10 |
| order | `CHECK(total_amount>=1000)` | BR-1.8, BR-7.11 |
| order | ограничения по времени доставки | BR-7.12–7.13 |
| payment | `UNIQUE(transaction_id)` | BR-8.3 |
| payment | уникальный частичный индекс успешного платежа | BR-8.1: не больше одной успешной попытки |
| payment | триггер суммы | BR-8.4: сумма попытки равна сумме заказа |
| order_structure | PK `(order_id,product_id)`, два FK | BR-7.14, BR-7.16: одно блюдо не повторяется |
| order_structure | `CHECK(quantity>0)` | BR-7.15 |
| order_structure | триггер соответствия ресторана | BR-7.3 |
| review | FK на пару `(order_id,client_id)` | BR-9.2: отзыв только от заказавшего клиента |
| review | `UNIQUE(order_id,entity_type,entity_id)` | BR-9.5: один отзыв на объект заказа |
| review | `CHECK(rating BETWEEN 1 AND 5)` | BR-9.4 |
| review | триггер проверки цели отзыва | BR-9.2, BR-9.5 |

У всех обязательных атрибутов `NOT NULL` в соответствии с BR-11.3–11.4. Поля с допустимым `NULL`: квартира/офис, фото блюда/отзыва, дата увольнения, дата доставки до завершения, агрегированные рейтинги при отсутствии отзывов. Enum-типы соответствуют BR-11.5.

Триггеры используются только там, где простого ограничения на строку недостаточно: сверка заказа и блюда, суммы заказа и платежа, объекта отзыва и контрольного заказа. Дополнительно триггер пересчитывает статус оплаты и агрегированный рейтинг.
