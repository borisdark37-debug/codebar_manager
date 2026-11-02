-- ==============================================================================
-- CodeBar Manager - Supabase PostgreSQL Schema & Security Migration
-- Project: mpcpofrzuifoqcqrqlke
-- Date: 2026-11-02
-- ==============================================================================

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ------------------------------------------------------------------------------
-- 2. Profiles Table (Linked to auth.users)
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT,
    role TEXT NOT NULL CHECK (role IN ('super_admin', 'admin', 'operator', 'manager')) DEFAULT 'operator',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by TEXT,
    disabled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- Index for fast user queries
CREATE INDEX IF NOT EXISTS idx_profiles_role ON public.profiles(role);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);

-- Trigger to auto-update updated_at on profiles
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- Trigger to handle new auth.users signup -> auto-insert into public.profiles
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    user_role TEXT;
    user_name TEXT;
BEGIN
    user_role := COALESCE(NEW.raw_user_meta_data->>'role', 'operator');
    user_name := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1));

    -- Assign super_admin if email matches known super admins
    IF LOWER(NEW.email) IN ('capucine@gmail.com', 'borisdark37@gmail.com') THEN
        user_role := 'super_admin';
    END IF;

    INSERT INTO public.profiles (id, email, full_name, role, is_active, created_at, updated_at)
    VALUES (
        NEW.id,
        NEW.email,
        user_name,
        user_role,
        TRUE,
        timezone('utc'::text, now()),
        timezone('utc'::text, now())
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
        role = CASE
            WHEN LOWER(NEW.email) IN ('capucine@gmail.com', 'borisdark37@gmail.com') THEN 'super_admin'
            ELSE EXCLUDED.role
        END,
        updated_at = timezone('utc'::text, now());

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- ------------------------------------------------------------------------------
-- 3. Products Table & Auto-Sequence CAP-%04d
-- ------------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.product_internal_code_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uuid UUID GENERATED ALWAYS AS (id) STORED,
    internal_code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    category TEXT DEFAULT '',
    format TEXT DEFAULT '',
    containment TEXT DEFAULT '',
    price NUMERIC(12, 2) NOT NULL DEFAULT 0.00,
    stock INTEGER NOT NULL DEFAULT 0,
    quantity INTEGER NOT NULL DEFAULT 0,
    code_type TEXT NOT NULL DEFAULT 'barcode128',
    barcode_svg TEXT,
    image_url TEXT,
    image_base64 TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    deleted_at TIMESTAMPTZ DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_products_internal_code ON public.products(internal_code);
CREATE INDEX IF NOT EXISTS idx_products_updated_at ON public.products(updated_at);
CREATE INDEX IF NOT EXISTS idx_products_deleted_at ON public.products(deleted_at);

-- Trigger for products auto-generating internal_code and updating sequence
CREATE OR REPLACE FUNCTION public.handle_product_internal_code()
RETURNS TRIGGER AS $$
DECLARE
    seq_val BIGINT;
    code_num BIGINT;
BEGIN
    NEW.updated_at := timezone('utc'::text, now());
    IF NEW.quantity IS NOT NULL AND NEW.stock = 0 THEN
        NEW.stock := NEW.quantity;
    ELSIF NEW.stock IS NOT NULL AND NEW.quantity = 0 THEN
        NEW.quantity := NEW.stock;
    END IF;

    -- If internal_code is missing or empty, generate CAP-XXXX
    IF NEW.internal_code IS NULL OR trim(NEW.internal_code) = '' THEN
        seq_val := nextval('public.product_internal_code_seq');
        NEW.internal_code := 'CAP-' || lpad(seq_val::text, 4, '0');
    ELSE
        -- If an internal code was provided (e.g. from client CAP-0042), update the sequence
        IF NEW.internal_code ~ '^CAP-[0-9]+$' THEN
            code_num := substring(NEW.internal_code from 5)::BIGINT;
            PERFORM setval('public.product_internal_code_seq', GREATEST(code_num, last_value))
            FROM public.product_internal_code_seq;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_products_internal_code ON public.products;
CREATE TRIGGER trg_products_internal_code
    BEFORE INSERT ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_product_internal_code();

DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW
    EXECUTE FUNCTION public.set_updated_at();

-- ------------------------------------------------------------------------------
-- 4. Activity Logs Table
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.activity_logs (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    user_email TEXT,
    action TEXT NOT NULL,
    entity_type TEXT,
    entity_id TEXT,
    metadata JSONB,
    ip_address TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_activity_logs_action ON public.activity_logs(action, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activity_logs_created_at ON public.activity_logs(created_at DESC);

-- ------------------------------------------------------------------------------
-- 5. Row Level Security (RLS) Configuration
-- ------------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

-- Helper function to check user role
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT AS $$
    SELECT role FROM public.profiles WHERE id = auth.uid();
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Profiles Policies
DROP POLICY IF EXISTS "Profiles are readable by authenticated users and anon" ON public.profiles;
CREATE POLICY "Profiles are readable by authenticated users and anon"
    ON public.profiles FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id OR public.current_user_role() = 'super_admin');

DROP POLICY IF EXISTS "Admins can insert profiles" ON public.profiles;
CREATE POLICY "Admins can insert profiles"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id OR public.current_user_role() IN ('super_admin', 'admin') OR auth.role() = 'anon');

DROP POLICY IF EXISTS "Super admin can delete profiles" ON public.profiles;
CREATE POLICY "Super admin can delete profiles"
    ON public.profiles FOR DELETE
    USING (public.current_user_role() = 'super_admin');

-- Products Policies (Seamless Offline-First & Realtime sync)
DROP POLICY IF EXISTS "Products are viewable by everyone" ON public.products;
CREATE POLICY "Products are viewable by everyone"
    ON public.products FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Products can be inserted by authenticated and anon" ON public.products;
CREATE POLICY "Products can be inserted by authenticated and anon"
    ON public.products FOR INSERT
    WITH CHECK (true);

DROP POLICY IF EXISTS "Products can be updated by authenticated and anon" ON public.products;
CREATE POLICY "Products can be updated by authenticated and anon"
    ON public.products FOR UPDATE
    USING (true);

DROP POLICY IF EXISTS "Products can be deleted by authenticated and anon" ON public.products;
CREATE POLICY "Products can be deleted by authenticated and anon"
    ON public.products FOR DELETE
    USING (true);

-- Activity Logs Policies
DROP POLICY IF EXISTS "Activity logs viewable by authenticated" ON public.activity_logs;
CREATE POLICY "Activity logs viewable by authenticated"
    ON public.activity_logs FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Activity logs insertable by anyone" ON public.activity_logs;
CREATE POLICY "Activity logs insertable by anyone"
    ON public.activity_logs FOR INSERT
    WITH CHECK (true);

-- ------------------------------------------------------------------------------
-- 6. Storage Buckets (product-images & barcode-svgs)
-- ------------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
    ('product-images', 'product-images', TRUE, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']),
    ('barcode-svgs', 'barcode-svgs', TRUE, 1048576, ARRAY['image/svg+xml', 'text/plain', 'text/xml'])
ON CONFLICT (id) DO UPDATE SET
    public = TRUE,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage RLS
DROP POLICY IF EXISTS "Public can view product images" ON storage.objects;
CREATE POLICY "Public can view product images"
    ON storage.objects FOR SELECT
    USING (bucket_id IN ('product-images', 'barcode-svgs'));

DROP POLICY IF EXISTS "Users can upload product images and svgs" ON storage.objects;
CREATE POLICY "Users can upload product images and svgs"
    ON storage.objects FOR INSERT
    WITH CHECK (bucket_id IN ('product-images', 'barcode-svgs'));

DROP POLICY IF EXISTS "Users can update product images and svgs" ON storage.objects;
CREATE POLICY "Users can update product images and svgs"
    ON storage.objects FOR UPDATE
    USING (bucket_id IN ('product-images', 'barcode-svgs'));

DROP POLICY IF EXISTS "Users can delete product images and svgs" ON storage.objects;
CREATE POLICY "Users can delete product images and svgs"
    ON storage.objects FOR DELETE
    USING (bucket_id IN ('product-images', 'barcode-svgs'));

-- ------------------------------------------------------------------------------
-- 7. Auto-Confirm Users & Seed Super Admin Profiles
-- ------------------------------------------------------------------------------
-- Auto-confirm any pending unconfirmed accounts (allows direct password login)
UPDATE auth.users
SET email_confirmed_at = timezone('utc'::text, now()),
    confirmed_at = timezone('utc'::text, now())
WHERE email_confirmed_at IS NULL;

-- Populate / ensure profiles for existing auth.users
INSERT INTO public.profiles (id, email, full_name, role, is_active)
SELECT
    u.id,
    u.email,
    COALESCE(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', split_part(u.email, '@', 1)),
    CASE
        WHEN LOWER(u.email) IN ('capucine@gmail.com', 'borisdark37@gmail.com') THEN 'super_admin'
        ELSE COALESCE(u.raw_user_meta_data->>'role', 'operator')
    END,
    TRUE
FROM auth.users u
ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    role = EXCLUDED.role;
