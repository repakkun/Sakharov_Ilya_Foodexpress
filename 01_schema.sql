CREATE SCHEMA IF NOT EXISTS sakharov_food;
SET search_path TO sakharov_food, public;

CREATE TYPE restaurant_status AS ENUM ('активен', 'неактивен');
CREATE TYPE product_status AS ENUM ('доступно', 'нет_в_наличии', 'архив');
CREATE TYPE courier_status AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен');
CREATE TYPE order_status AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен', 'отменён');
CREATE TYPE order_pay_status AS ENUM ('ожидает', 'оплачен', 'ошибка');
CREATE TYPE payment_status AS ENUM ('успех', 'ошибка', 'в_обработке');
CREATE TYPE payment_type AS ENUM ('карта', 'наличные', 'безнал');
CREATE TYPE review_entity_type AS ENUM ('блюдо', 'ресторан', 'заказ');

CREATE TABLE client (
 client_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 login varchar(100) NOT NULL UNIQUE,
 password varchar(32) NOT NULL,
 phone_number char(11) NOT NULL UNIQUE
);
CREATE TABLE address (
 address_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 street varchar(150) NOT NULL,
 house_number varchar(20) NOT NULL,
 apartment_office varchar(20),
 UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office)
);
CREATE TABLE client_address (
 client_id uuid NOT NULL REFERENCES client(client_id),
 address_id uuid NOT NULL REFERENCES address(address_id),
 PRIMARY KEY(client_id, address_id)
);
CREATE TABLE restaurant (
 restaurant_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 restaurant_name varchar(150) NOT NULL,
 address_id uuid NOT NULL UNIQUE REFERENCES address(address_id),
 description text NOT NULL,
 work_start time NOT NULL,
 work_end time NOT NULL,
 company_details text NOT NULL,
 rating numeric(3,2),
 status restaurant_status NOT NULL,
 CHECK (work_end > work_start),
 CHECK (rating BETWEEN 0 AND 5)
);
CREATE TABLE courier (
 courier_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 fio varchar(150) NOT NULL,
 phone_number char(11) NOT NULL UNIQUE,
 status courier_status NOT NULL,
 hire_date date NOT NULL,
 dismissal_date date,
 coefficient numeric(3,2) NOT NULL DEFAULT 0.1,
 CHECK (coefficient BETWEEN 0.1 AND 0.5),
 CHECK ((status = 'уволен' AND dismissal_date IS NOT NULL) OR (status <> 'уволен' AND dismissal_date IS NULL)),
 CHECK (dismissal_date IS NULL OR dismissal_date >= hire_date)
);
CREATE TABLE courier_pay (
 year int NOT NULL,
 month int NOT NULL,
 courier_id uuid NOT NULL REFERENCES courier(courier_id),
 amount numeric(14,2) NOT NULL,
 coefficient_used numeric(3,2) NOT NULL,
 PRIMARY KEY(year, month, courier_id),
 CHECK (month BETWEEN 1 AND 12),
 CHECK (amount >= 0),
 CHECK (coefficient_used BETWEEN 0.1 AND 0.5)
);
CREATE TABLE product_category (
 product_category_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 product_category_name varchar(100) NOT NULL UNIQUE
);
CREATE TABLE product (
 product_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 product_name varchar(150) NOT NULL,
 product_category_id uuid NOT NULL REFERENCES product_category(product_category_id),
 price numeric(12,2) NOT NULL CHECK (price >= 0),
 restaurant_id uuid NOT NULL REFERENCES restaurant(restaurant_id),
 photo_url text,
 rating numeric(3,2) CHECK (rating BETWEEN 0 AND 5),
 status product_status NOT NULL,
 description text NOT NULL,
 UNIQUE(product_id, restaurant_id)
);
CREATE TABLE "order" (
 order_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 courier_id uuid NOT NULL REFERENCES courier(courier_id),
 client_id uuid NOT NULL REFERENCES client(client_id),
 address_id uuid NOT NULL REFERENCES address(address_id),
 restaurant_id uuid NOT NULL REFERENCES restaurant(restaurant_id),
 order_timestamp timestamp NOT NULL,
 delivery_timestamp timestamp,
 order_amount numeric(14,2) NOT NULL,
 commission numeric(14,2) NOT NULL,
 total_amount numeric(14,2) NOT NULL,
 status order_status NOT NULL,
 pay_status order_pay_status NOT NULL,
 description text NOT NULL,
 FOREIGN KEY (client_id, address_id) REFERENCES client_address(client_id, address_id),
 UNIQUE(order_id, restaurant_id),
 UNIQUE(order_id, client_id),
 CHECK (order_amount >= 0),
 CHECK (commission = round(order_amount * 0.10, 2)),
 CHECK (total_amount = order_amount + commission),
 CHECK (total_amount >= 1000),
 CHECK (delivery_timestamp IS NULL OR delivery_timestamp >= order_timestamp),
 CHECK ((status = 'доставлен' AND delivery_timestamp IS NOT NULL) OR status <> 'доставлен')
);
CREATE TABLE payment (
 payment_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 order_id uuid NOT NULL REFERENCES "order"(order_id),
 payment_type payment_type NOT NULL,
 amount numeric(14,2) NOT NULL CHECK (amount >= 0),
 transaction_id varchar(150) NOT NULL UNIQUE,
 transaction_timestamp timestamp NOT NULL,
 status payment_status NOT NULL
);
CREATE UNIQUE INDEX payment_one_success ON payment (order_id) WHERE status = 'успех';
CREATE TABLE order_structure (
 order_id uuid NOT NULL REFERENCES "order"(order_id),
 product_id uuid NOT NULL REFERENCES product(product_id),
 quantity numeric(12,3) NOT NULL CHECK (quantity > 0),
 PRIMARY KEY(order_id, product_id)
);
CREATE TABLE review (
 review_id uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),
 client_id uuid NOT NULL REFERENCES client(client_id),
 review_timestamp timestamp NOT NULL,
 entity_id uuid NOT NULL,
 entity_type review_entity_type NOT NULL,
 order_id uuid NOT NULL,
 description text NOT NULL,
 photo_url text,
 rating numeric(3,2) NOT NULL CHECK (rating BETWEEN 1 AND 5),
 FOREIGN KEY (order_id, client_id) REFERENCES "order"(order_id, client_id),
 UNIQUE (order_id, entity_type, entity_id)
);

-- Проверки связей между таблицами.
CREATE FUNCTION check_order_product() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM "order" o JOIN product p ON p.product_id = NEW.product_id
  WHERE o.order_id = NEW.order_id AND o.restaurant_id = p.restaurant_id
 ) THEN RAISE EXCEPTION 'Блюдо должно принадлежать ресторану заказа'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER order_product_check BEFORE INSERT OR UPDATE ON order_structure
 FOR EACH ROW EXECUTE FUNCTION check_order_product();

CREATE FUNCTION check_payment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM "order" WHERE order_id = NEW.order_id AND total_amount = NEW.amount) THEN
  RAISE EXCEPTION 'Сумма платежа должна равняться сумме заказа'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER payment_amount_check BEFORE INSERT OR UPDATE ON payment
 FOR EACH ROW EXECUTE FUNCTION check_payment();

CREATE FUNCTION refresh_order_payment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_id uuid;
BEGIN
 v_id := COALESCE(NEW.order_id, OLD.order_id);
 UPDATE "order" SET pay_status = CASE
   WHEN EXISTS(SELECT 1 FROM payment WHERE order_id=v_id AND status='успех') THEN 'оплачен'::order_pay_status
   WHEN EXISTS(SELECT 1 FROM payment WHERE order_id=v_id AND status='в_обработке') THEN 'ожидает'::order_pay_status
   WHEN EXISTS(SELECT 1 FROM payment WHERE order_id=v_id) THEN 'ошибка'::order_pay_status
   ELSE 'ожидает'::order_pay_status END
 WHERE order_id = v_id;
 IF TG_OP='UPDATE' AND OLD.order_id <> NEW.order_id THEN
   UPDATE "order" SET pay_status = CASE
     WHEN EXISTS(SELECT 1 FROM payment WHERE order_id=OLD.order_id AND status='успех') THEN 'оплачен'::order_pay_status
     WHEN EXISTS(SELECT 1 FROM payment WHERE order_id=OLD.order_id AND status='в_обработке') THEN 'ожидает'::order_pay_status
     WHEN EXISTS(SELECT 1 FROM payment WHERE order_id=OLD.order_id) THEN 'ошибка'::order_pay_status
     ELSE 'ожидает'::order_pay_status END WHERE order_id=OLD.order_id;
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER payment_order_status AFTER INSERT OR UPDATE OR DELETE ON payment
 FOR EACH ROW EXECUTE FUNCTION refresh_order_payment();

CREATE FUNCTION check_review_target() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_rest uuid;
BEGIN
 SELECT restaurant_id INTO v_rest FROM "order" WHERE order_id=NEW.order_id AND client_id=NEW.client_id;
 IF v_rest IS NULL THEN RAISE EXCEPTION 'Отзыв должен принадлежать заказу клиента'; END IF;
 IF NEW.entity_type='заказ' AND NEW.entity_id <> NEW.order_id THEN
  RAISE EXCEPTION 'Неверный идентификатор заказа для отзыва';
 ELSIF NEW.entity_type='ресторан' AND NEW.entity_id <> v_rest THEN
  RAISE EXCEPTION 'Ресторан в отзыве не совпадает с заказом';
 ELSIF NEW.entity_type='блюдо' AND NOT EXISTS (
   SELECT 1 FROM order_structure WHERE order_id=NEW.order_id AND product_id=NEW.entity_id
 ) THEN RAISE EXCEPTION 'Нельзя оценивать блюдо вне заказа'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER review_target_check BEFORE INSERT OR UPDATE ON review
 FOR EACH ROW EXECUTE FUNCTION check_review_target();
