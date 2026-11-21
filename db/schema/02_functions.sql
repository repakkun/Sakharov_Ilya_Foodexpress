SET search_path TO sakharov_food, public;

-- Пересчёт рейтинга при изменении отзывов.
CREATE FUNCTION rating_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN
        IF OLD.entity_type = 'блюдо' THEN
            UPDATE product
            SET rating = (SELECT AVG(rating) FROM review
                          WHERE entity_type = 'блюдо' AND entity_id = OLD.entity_id)
            WHERE product_id = OLD.entity_id;
        ELSIF OLD.entity_type = 'ресторан' THEN
            UPDATE restaurant
            SET rating = (SELECT AVG(rating) FROM review
                          WHERE entity_type = 'ресторан' AND entity_id = OLD.entity_id)
            WHERE restaurant_id = OLD.entity_id;
        END IF;
    END IF;

    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        IF NEW.entity_type = 'блюдо' THEN
            UPDATE product
            SET rating = (SELECT AVG(rating) FROM review
                          WHERE entity_type = 'блюдо' AND entity_id = NEW.entity_id)
            WHERE product_id = NEW.entity_id;
        ELSIF NEW.entity_type = 'ресторан' THEN
            UPDATE restaurant
            SET rating = (SELECT AVG(rating) FROM review
                          WHERE entity_type = 'ресторан' AND entity_id = NEW.entity_id)
            WHERE restaurant_id = NEW.entity_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER review_rating
AFTER INSERT OR UPDATE OR DELETE ON review
FOR EACH ROW EXECUTE FUNCTION rating_change();

-- Добавление нового блюда.
CREATE PROCEDURE add_product(
    p_product_name varchar,
    p_product_category_id uuid,
    p_price numeric,
    p_restaurant_id uuid,
    p_photo_url text,
    p_rating numeric,
    p_status product_status,
    p_description text
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM restaurant WHERE restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'Ресторан не найден';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM product_category
                   WHERE product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'Категория не найдена';
    END IF;

    INSERT INTO product (product_name, product_category_id, price,
                         restaurant_id, photo_url, rating, status, description)
    VALUES (p_product_name, p_product_category_id, p_price,
            p_restaurant_id, p_photo_url, p_rating, p_status, p_description);
END;
$$;

-- Удаление записей без удаления самих таблиц.
CREATE PROCEDURE erase_test_data()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE review, payment, order_structure, courier_pay,
                   "order", product, restaurant, client_address,
                   address, client, courier, product_category;
END;
$$;

-- Расчёт зарплаты по каждому курьеру за текущий месяц.
CREATE PROCEDURE courier_salary()
LANGUAGE plpgsql
AS $$
DECLARE
    c record;
    delivered_count integer;
    total_commission numeric;
    new_coefficient numeric;
BEGIN
    FOR c IN SELECT courier_id, coefficient, status FROM courier LOOP
        SELECT COUNT(*), COALESCE(SUM(commission), 0)
        INTO delivered_count, total_commission
        FROM "order"
        WHERE courier_id = c.courier_id
          AND status = 'доставлен'
          AND delivery_timestamp >= date_trunc('month', CURRENT_DATE)
          AND delivery_timestamp < date_trunc('month', CURRENT_DATE) + INTERVAL '1 month';

        INSERT INTO courier_pay (year, month, courier_id, amount, coefficient_used)
        VALUES (EXTRACT(YEAR FROM CURRENT_DATE)::int,
                EXTRACT(MONTH FROM CURRENT_DATE)::int,
                c.courier_id,
                ROUND(total_commission * c.coefficient, 2),
                c.coefficient)
        ON CONFLICT (year, month, courier_id)
        DO UPDATE SET amount = EXCLUDED.amount,
                      coefficient_used = EXCLUDED.coefficient_used;

        IF delivered_count <= 150 THEN
            new_coefficient := 0.1;
        ELSIF delivered_count <= 250 THEN
            new_coefficient := 0.2;
        ELSIF delivered_count <= 500 THEN
            new_coefficient := 0.3;
        ELSE
            new_coefficient := 0.5;
        END IF;

        IF c.status <> 'уволен' THEN
            UPDATE courier SET coefficient = new_coefficient
            WHERE courier_id = c.courier_id;
        END IF;
    END LOOP;
END;
$$;
