# Проверка базы FoodExpress

Запускать после `01_schema.sql`, `02_functions.sql`, `03_generator.sql`, `grants.sql`.

```sql
SET search_path TO sakharov_food, public;
CALL insert_test_data(10);
-- Повторный запуск также должен пройти без ошибок:
CALL insert_test_data(10);

SELECT 'client' AS name, COUNT(*) FROM client
UNION ALL SELECT 'restaurant', COUNT(*) FROM restaurant
UNION ALL SELECT 'courier', COUNT(*) FROM courier
UNION ALL SELECT 'product', COUNT(*) FROM product
UNION ALL SELECT 'order', COUNT(*) FROM "order"
UNION ALL SELECT 'payment', COUNT(*) FROM payment
UNION ALL SELECT 'review', COUNT(*) FROM review;

CALL courier_salary();
SELECT * FROM courier_pay LIMIT 10;

-- Данные из существующих записей:
SELECT * FROM product LIMIT 5;
SELECT * FROM restaurant LIMIT 5;
```

Проверить, что есть данные в каждой таблице, а UUID-связи не нарушаются. `insert_test_data(10)` при первом запуске должен создавать 10 клиентов, 10 ресторанов, 10 курьеров, 50 блюд, 50 заказов, 50 платежей и 50 отзывов; при втором запуске значения удваиваются. Дополнительные таблицы тоже должны заполняться.

Для проверки `add_product` возьми действующие UUID ресторана и категории из результата SELECT и вызови процедуру с ними. Для проверки рейтинга добавь/удали отзыв с корректными `client_id`, `order_id` и `entity_id`, затем проверь поле `rating` у блюда/ресторана.

Под пользователем `inspector` проверь вызовы `insert_test_data(10)`, `erase_test_data()`, `add_product(...)`, `courier_salary()` и доступность `information_schema.tables`. Если вызываешь `erase_test_data()`, потом снова сгенерируй данные для резервной копии.

FOOD-106 (`get_statistic`) и FOOD-108 (`how_much_money`) здесь намеренно отсутствуют.
