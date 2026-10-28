-- ============================================================================
-- JHADIMADI.COM — SUPABASE SQL DATABASE & SECURITY SCHEMA (COMPACT VERSION)
-- Single Backend: Supabase Only (Auth, PostgreSQL, RLS, Storage)
-- Architecture: Strictly Enforced RBAC, Server-Side Validation, and Secure RLS
-- ============================================================================

-- ============================================================================
-- STEP 1: EXTENSIONS
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- STEP 2: ENUMS
-- ============================================================================
DO $$ BEGIN
  CREATE TYPE public.account_status AS ENUM ('active', 'inactive', 'suspended', 'pending', 'deleted');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE public.user_role AS ENUM ('customer', 'seller', 'freelancer', 'service_provider', 'member', 'moderator', 'admin', 'super_admin');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE public.verification_status AS ENUM ('pending', 'approved', 'rejected', 'suspended');
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- STEP 3: REUSABLE UTILITIES & TRIGGER FUNCTIONS
-- ============================================================================

-- 3.1 Generic updated_at timestamp refresher
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- ============================================================================
-- STEP 4: CORE TABLES (profiles & user_roles)
-- ============================================================================

-- 4.1 Master Profiles Table (1-to-1 with auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name TEXT NOT NULL DEFAULT '',
  username TEXT UNIQUE,
  email TEXT,
  phone TEXT,
  avatar_url TEXT,
  district TEXT,
  upazila TEXT,
  address TEXT,
  bio TEXT,
  account_status public.account_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles(username);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON public.profiles(phone);

-- 4.2 User Roles Table (1 User -> Multiple Roles)
CREATE TABLE IF NOT EXISTS public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role public.user_role NOT NULL DEFAULT 'customer',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, role)
);

CREATE INDEX IF NOT EXISTS idx_user_roles_user_id ON public.user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_user_roles_role ON public.user_roles(role);

-- ============================================================================
-- STEP 5: CONDITIONAL ROLE PROFILE TABLES
-- ============================================================================

-- 5.1 Seller Profiles
CREATE TABLE IF NOT EXISTS public.seller_profiles (
  id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  business_name TEXT NOT NULL,
  business_phone TEXT,
  business_address TEXT,
  district TEXT,
  upazila TEXT,
  business_logo TEXT,
  business_cover TEXT,
  verification_status public.verification_status NOT NULL DEFAULT 'pending',
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5.2 Freelancer Profiles
CREATE TABLE IF NOT EXISTS public.freelancer_profiles (
  id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  professional_title TEXT,
  skills TEXT[] DEFAULT '{}',
  hourly_rate NUMERIC(10,2),
  bio TEXT,
  portfolio_url TEXT,
  verification_status public.verification_status NOT NULL DEFAULT 'pending',
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5.3 Service Provider Profiles
CREATE TABLE IF NOT EXISTS public.service_provider_profiles (
  id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  provider_name TEXT NOT NULL,
  category TEXT NOT NULL,
  service_areas TEXT[] DEFAULT '{}',
  phone TEXT,
  nid_verified BOOLEAN DEFAULT FALSE,
  verification_status public.verification_status NOT NULL DEFAULT 'pending',
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5.4 Member Profiles
CREATE TABLE IF NOT EXISTS public.member_profiles (
  id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  membership_id TEXT UNIQUE,
  membership_tier TEXT DEFAULT 'general',
  verification_status public.verification_status NOT NULL DEFAULT 'approved',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- STEP 6: MARKETPLACE & BUSINESS TABLES
-- ============================================================================

-- 6.1 Products Table (Price, Stock & Status strictly enforced)
CREATE TABLE IF NOT EXISTS public.products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id UUID NOT NULL REFERENCES public.seller_profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  slug TEXT,
  description TEXT,
  category TEXT NOT NULL,
  price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  discount_price NUMERIC(12,2) CHECK (discount_price >= 0 AND discount_price <= price),
  stock INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
  unit TEXT DEFAULT 'piece',
  is_published BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_seller ON public.products(seller_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON public.products(category);
CREATE INDEX IF NOT EXISTS idx_products_published ON public.products(is_published);

-- 6.2 Product Images Table (Multiple images per product)
CREATE TABLE IF NOT EXISTS public.product_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  display_order INTEGER NOT NULL DEFAULT 0,
  is_primary BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_product_images_product ON public.product_images(product_id);

-- 6.3 Services Table
CREATE TABLE IF NOT EXISTS public.services (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES public.service_provider_profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT NOT NULL,
  base_price NUMERIC(12,2) NOT NULL CHECK (base_price >= 0),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  verification_status public.verification_status NOT NULL DEFAULT 'approved',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_services_provider ON public.services(provider_id);
CREATE INDEX IF NOT EXISTS idx_services_category ON public.services(category);

-- 6.4 Orders Table
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE RESTRICT,
  order_number TEXT UNIQUE NOT NULL DEFAULT ('ORD-' || upper(substr(gen_random_uuid()::text, 1, 8))),
  total_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded')),
  payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid', 'partially_paid', 'refunded')),
  payment_method TEXT DEFAULT 'cod',
  shipping_address JSONB NOT NULL DEFAULT '{}'::jsonb,
  customer_notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_customer ON public.orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);

-- 6.5 Order Items Table (Server-side price snapshot and stock check)
CREATE TABLE IF NOT EXISTS public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  seller_id UUID NOT NULL REFERENCES public.seller_profiles(id) ON DELETE RESTRICT,
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0),
  subtotal NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_seller ON public.order_items(seller_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON public.order_items(product_id);

-- 6.6 Security Logs Table (Auditing without storing passwords/secrets)
CREATE TABLE IF NOT EXISTS public.security_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  details JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_security_logs_user ON public.security_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_security_logs_action ON public.security_logs(action);
CREATE INDEX IF NOT EXISTS idx_security_logs_created_at ON public.security_logs(created_at DESC);

-- ============================================================================
-- STEP 7: SECURITY HELPER FUNCTIONS
-- ============================================================================

-- 7.1 Check if a user possesses a specific role
CREATE OR REPLACE FUNCTION public.has_role(user_uuid UUID, required_role public.user_role)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_roles
    WHERE user_id = user_uuid AND role = required_role
  );
$$;

-- 7.2 Check if user is an admin or super_admin
CREATE OR REPLACE FUNCTION public.is_admin(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
STABLE
AS $$
DECLARE
  v_res BOOLEAN := false;
BEGIN
  IF user_uuid IS NULL THEN RETURN false; END IF;
  IF to_regclass('public.user_roles') IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = user_uuid AND role IN ('admin', 'super_admin')
    ) INTO v_res;
  END IF;
  RETURN COALESCE(v_res, false);
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

-- 7.3 Check if user is staff (moderator, admin, or super_admin)
CREATE OR REPLACE FUNCTION public.is_staff(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
STABLE
AS $$
DECLARE
  v_res BOOLEAN := false;
BEGIN
  IF user_uuid IS NULL THEN RETURN false; END IF;
  IF to_regclass('public.user_roles') IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = user_uuid AND role IN ('moderator', 'admin', 'super_admin')
    ) INTO v_res;
  END IF;
  RETURN COALESCE(v_res, false);
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

-- 7.4 Check if user is a super_admin
CREATE OR REPLACE FUNCTION public.is_super_admin(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
STABLE
AS $$
DECLARE
  v_res BOOLEAN := false;
BEGIN
  IF user_uuid IS NULL THEN RETURN false; END IF;
  IF to_regclass('public.user_roles') IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1 FROM public.user_roles
      WHERE user_id = user_uuid AND role = 'super_admin'
    ) INTO v_res;
  END IF;
  RETURN COALESCE(v_res, false);
EXCEPTION WHEN OTHERS THEN
  RETURN false;
END;
$$;

-- ============================================================================
-- STEP 8: AUTOMATIC USER CREATION & ROLE ASSIGNMENT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, auth
LANGUAGE plpgsql
AS $$
BEGIN
  -- 1. Insert Profile from Auth Metadata
  INSERT INTO public.profiles (
    id,
    full_name,
    email,
    phone,
    avatar_url,
    account_status
  ) VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
    NEW.email,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
    'active'::public.account_status
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
    updated_at = NOW();

  -- 2. Default Role: 'customer'
  INSERT INTO public.user_roles (user_id, role)
  VALUES (NEW.id, 'customer'::public.user_role)
  ON CONFLICT (user_id, role) DO NOTHING;

  -- 3. Audit log user creation
  INSERT INTO public.security_logs (user_id, action, details)
  VALUES (NEW.id, 'USER_REGISTERED', jsonb_build_object('email', NEW.email, 'provider', NEW.raw_app_meta_data->>'provider'));

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================================
-- STEP 9: SECURE SERVER-SIDE ROLE ASSIGNMENT (Super Admin Only)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.assign_user_role(
  target_user_id UUID,
  new_role public.user_role
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Only super_admin may execute this function
  IF NOT public.is_super_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Access Denied: Only Super Admin can change user roles.';
  END IF;

  INSERT INTO public.user_roles (user_id, role)
  VALUES (target_user_id, new_role)
  ON CONFLICT (user_id, role) DO NOTHING;

  -- Security log the privilege alteration
  INSERT INTO public.security_logs (user_id, action, details)
  VALUES (
    auth.uid(),
    'ROLE_ASSIGNED',
    jsonb_build_object('target_user', target_user_id, 'assigned_role', new_role)
  );
END;
$$;

-- ============================================================================
-- STEP 10: SERVER-SIDE PRICE, STOCK & ORDER INTEGRITY TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION public.validate_order_item_integrity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_real_price NUMERIC(12,2);
  v_real_stock INTEGER;
  v_seller_id UUID;
BEGIN
  -- Fetch actual price and stock from products table directly to avoid frontend tampering
  SELECT 
    COALESCE(discount_price, price), 
    stock, 
    seller_id 
  INTO 
    v_real_price, 
    v_real_stock, 
    v_seller_id
  FROM public.products
  WHERE id = NEW.product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found.';
  END IF;

  IF v_real_stock < NEW.quantity THEN
    RAISE EXCEPTION 'Insufficient product stock.';
  END IF;

  -- Overwrite price with database authoritative values
  NEW.unit_price := v_real_price;
  NEW.subtotal := v_real_price * NEW.quantity;
  NEW.seller_id := v_seller_id;

  -- Atomically deduct stock
  UPDATE public.products
  SET stock = stock - NEW.quantity, updated_at = NOW()
  WHERE id = NEW.product_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_item_integrity ON public.order_items;
CREATE TRIGGER trg_order_item_integrity
  BEFORE INSERT ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION public.validate_order_item_integrity();

-- Attach updated_at triggers
DROP TRIGGER IF EXISTS trg_profiles_updated_at ON public.profiles;
CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_seller_updated_at ON public.seller_profiles;
CREATE TRIGGER trg_seller_updated_at BEFORE UPDATE ON public.seller_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_freelancer_updated_at ON public.freelancer_profiles;
CREATE TRIGGER trg_freelancer_updated_at BEFORE UPDATE ON public.freelancer_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_sp_updated_at ON public.service_provider_profiles;
CREATE TRIGGER trg_sp_updated_at BEFORE UPDATE ON public.service_provider_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_member_updated_at ON public.member_profiles;
CREATE TRIGGER trg_member_updated_at BEFORE UPDATE ON public.member_profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_services_updated_at ON public.services;
CREATE TRIGGER trg_services_updated_at BEFORE UPDATE ON public.services FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_orders_updated_at ON public.orders;
CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================================
-- STEP 11: ROW LEVEL SECURITY (RLS) & ACCESS CONTROL POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.freelancer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.service_provider_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.security_logs ENABLE ROW LEVEL SECURITY;

-- 11.1 Profiles Policies
CREATE POLICY "Public can view basic active profiles"
  ON public.profiles FOR SELECT
  USING (account_status = 'active');

CREATE POLICY "Users can view and update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Staff can view and manage all profiles"
  ON public.profiles FOR ALL
  USING (public.is_staff(auth.uid()));

-- 11.2 User Roles Policies
CREATE POLICY "Users can view own roles"
  ON public.user_roles FOR SELECT
  USING (auth.uid() = user_id OR public.is_staff(auth.uid()));

CREATE POLICY "Only Super Admins can alter roles directly"
  ON public.user_roles FOR ALL
  USING (public.is_super_admin(auth.uid()))
  WITH CHECK (public.is_super_admin(auth.uid()));

-- 11.3 Role Profiles Policies (Seller, Freelancer, Service Provider, Member)
-- Seller
CREATE POLICY "Public can view approved seller profiles"
  ON public.seller_profiles FOR SELECT
  USING (verification_status = 'approved' OR auth.uid() = id OR public.is_staff(auth.uid()));

CREATE POLICY "Users can insert own seller profile"
  ON public.seller_profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own seller profile"
  ON public.seller_profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Staff can manage all seller profiles"
  ON public.seller_profiles FOR ALL
  USING (public.is_staff(auth.uid()));

-- Freelancer
CREATE POLICY "Public can view approved freelancer profiles"
  ON public.freelancer_profiles FOR SELECT
  USING (verification_status = 'approved' OR auth.uid() = id OR public.is_staff(auth.uid()));

CREATE POLICY "Users can insert own freelancer profile"
  ON public.freelancer_profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own freelancer profile"
  ON public.freelancer_profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Staff can manage all freelancer profiles"
  ON public.freelancer_profiles FOR ALL
  USING (public.is_staff(auth.uid()));

-- Service Provider
CREATE POLICY "Public can view approved service provider profiles"
  ON public.service_provider_profiles FOR SELECT
  USING (verification_status = 'approved' OR auth.uid() = id OR public.is_staff(auth.uid()));

CREATE POLICY "Users can insert own service provider profile"
  ON public.service_provider_profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own service provider profile"
  ON public.service_provider_profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Staff can manage all service provider profiles"
  ON public.service_provider_profiles FOR ALL
  USING (public.is_staff(auth.uid()));

-- Member
CREATE POLICY "Public can view approved member profiles"
  ON public.member_profiles FOR SELECT
  USING (verification_status = 'approved' OR auth.uid() = id OR public.is_staff(auth.uid()));

CREATE POLICY "Users can insert own member profile"
  ON public.member_profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own member profile"
  ON public.member_profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Staff can manage all member profiles"
  ON public.member_profiles FOR ALL
  USING (public.is_staff(auth.uid()));

-- 11.4 Products & Product Images Policies
CREATE POLICY "Public can view published products"
  ON public.products FOR SELECT
  USING (is_published = TRUE OR auth.uid() = seller_id OR public.is_staff(auth.uid()));

CREATE POLICY "Sellers can manage own products"
  ON public.products FOR ALL
  USING (auth.uid() = seller_id OR public.is_staff(auth.uid()))
  WITH CHECK (auth.uid() = seller_id OR public.is_staff(auth.uid()));

CREATE POLICY "Public can view product images"
  ON public.product_images FOR SELECT
  USING (TRUE);

CREATE POLICY "Sellers can manage product images"
  ON public.product_images FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.products
      WHERE products.id = product_images.product_id
        AND (products.seller_id = auth.uid() OR public.is_staff(auth.uid()))
    )
  );

-- 11.5 Services Policies
CREATE POLICY "Public can view active services"
  ON public.services FOR SELECT
  USING (is_active = TRUE OR auth.uid() = provider_id OR public.is_staff(auth.uid()));

CREATE POLICY "Providers can manage own services"
  ON public.services FOR ALL
  USING (auth.uid() = provider_id OR public.is_staff(auth.uid()))
  WITH CHECK (auth.uid() = provider_id OR public.is_staff(auth.uid()));

-- 11.6 Orders Policies
CREATE POLICY "Customers can view own orders"
  ON public.orders FOR SELECT
  USING (auth.uid() = customer_id OR public.is_staff(auth.uid()));

CREATE POLICY "Customers can insert own orders"
  ON public.orders FOR INSERT
  WITH CHECK (auth.uid() = customer_id);

CREATE POLICY "Staff can update and manage orders"
  ON public.orders FOR UPDATE
  USING (public.is_staff(auth.uid()));

-- 11.7 Order Items Policies
CREATE POLICY "Customers and Sellers can view their order items"
  ON public.order_items FOR SELECT
  USING (
    auth.uid() = seller_id
    OR EXISTS (
      SELECT 1 FROM public.orders
      WHERE orders.id = order_items.order_id AND orders.customer_id = auth.uid()
    )
    OR public.is_staff(auth.uid())
  );

CREATE POLICY "Customers can insert order items"
  ON public.order_items FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders
      WHERE orders.id = order_items.order_id AND orders.customer_id = auth.uid()
    )
  );

-- 11.8 Security Logs Policies (Append-only for users, read own logs)
CREATE POLICY "Users can view only own security logs"
  ON public.security_logs FOR SELECT
  USING (auth.uid() = user_id OR public.is_staff(auth.uid()));

CREATE POLICY "Authenticated users can create security log"
  ON public.security_logs FOR INSERT
  WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- Prevent any UPDATE or DELETE on security logs (Immutability guarantee)
-- Note: No UPDATE or DELETE policies are granted to anyone.

-- ============================================================================
-- STEP 12: SUPABASE STORAGE BUCKETS & ISOLATION POLICIES
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  ('products', 'products', true, 20971520, ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/svg+xml']),
  ('avatars', 'avatars', true, 5242880, ARRAY['image/png', 'image/jpeg', 'image/webp']),
  ('business-media', 'business-media', true, 10485760, ARRAY['image/png', 'image/jpeg', 'image/webp']),
  ('banners', 'banners', true, 10485760, ARRAY['image/png', 'image/jpeg', 'image/webp']),
  ('service-media', 'service-media', true, 10485760, ARRAY['image/png', 'image/jpeg', 'image/webp']),
  ('portfolio-files', 'portfolio-files', false, 20971520, NULL),
  ('documents', 'documents', false, 20971520, ARRAY['application/pdf', 'image/png', 'image/jpeg'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Storage RLS: Public reading of public buckets
CREATE POLICY "Public Read for Public Buckets"
  ON storage.objects FOR SELECT
  USING (bucket_id IN ('products', 'avatars', 'business-media', 'banners', 'service-media', 'product-images', 'public-banners'));

-- Storage RLS: Allow uploads to products and asset buckets
CREATE POLICY "Allow upload to products bucket"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id IN ('products', 'banners', 'product-images', 'avatars', 'business-media', 'service-media', 'public-banners')
  );

CREATE POLICY "Allow update in products bucket"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id IN ('products', 'banners', 'product-images', 'avatars', 'business-media', 'service-media', 'public-banners')
  );

CREATE POLICY "Allow delete in products bucket"
  ON storage.objects FOR DELETE
  USING (
    bucket_id IN ('products', 'banners', 'product-images', 'avatars', 'business-media', 'service-media', 'public-banners')
  );

-- Storage RLS: Users can only upload and modify within their own user_id folder for other buckets
CREATE POLICY "Users upload to own folder"
  ON storage.objects FOR INSERT
  WITH CHECK (
    auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users update own files"
  ON storage.objects FOR UPDATE
  USING (
    auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users delete own files"
  ON storage.objects FOR DELETE
  USING (
    auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Staff can access and manage all files across all buckets
CREATE POLICY "Staff Full Access to Storage"
  ON storage.objects FOR ALL
  USING (public.is_staff(auth.uid()));

-- ============================================================================
-- STEP 13: JHADIMADI.COM — MIGRATION 025: J-PAY WALLET ATOMIC LEDGER
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.wallets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  phone TEXT,
  balance NUMERIC(14, 2) NOT NULL DEFAULT 0.00 CHECK (balance >= 0),
  pending_escrow NUMERIC(14, 2) NOT NULL DEFAULT 0.00 CHECK (pending_escrow >= 0),
  total_deposited NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
  total_withdrawn NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
  total_spent NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
  total_earned NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
  currency TEXT NOT NULL DEFAULT 'BDT',
  is_frozen BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON public.wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_phone ON public.wallets(phone);

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  wallet_id UUID NOT NULL REFERENCES public.wallets(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN (
    'add_money', 'transfer_in', 'transfer_out', 'purchase',
    'escrow_hold', 'escrow_release', 'earning', 'withdrawal', 'refund', 'fee'
  )),
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  fee NUMERIC(14, 2) NOT NULL DEFAULT 0.00,
  balance_before NUMERIC(14, 2) NOT NULL,
  balance_after NUMERIC(14, 2) NOT NULL,
  status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'failed', 'cancelled', 'rejected')),
  payment_method TEXT,
  trx_id TEXT,
  sender_number TEXT,
  receiver_number TEXT,
  counterpart_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reference_id TEXT,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_id ON public.wallet_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_wallet_id ON public.wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_created_at ON public.wallet_transactions(created_at DESC);

CREATE TABLE IF NOT EXISTS public.wallet_add_money_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  payment_method TEXT NOT NULL,
  trx_id TEXT NOT NULL,
  sender_number TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_note TEXT,
  approved_by UUID REFERENCES auth.users(id),
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_add_money_user_id ON public.wallet_add_money_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_add_money_status ON public.wallet_add_money_requests(status);

CREATE TABLE IF NOT EXISTS public.wallet_withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(14, 2) NOT NULL CHECK (amount > 0),
  payout_method TEXT NOT NULL,
  payout_number TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'processing')),
  admin_note TEXT,
  processed_by UUID REFERENCES auth.users(id),
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_withdrawals_user_id ON public.wallet_withdrawals(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_status ON public.wallet_withdrawals(status);

-- RPC 1: wallet_add_money_approve
CREATE OR REPLACE FUNCTION public.wallet_add_money_approve(
  p_request_id UUID,
  p_admin_id UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_req RECORD;
  v_wallet RECORD;
  v_before NUMERIC;
  v_after NUMERIC;
  v_tx_id UUID;
BEGIN
  SELECT * INTO v_req FROM public.wallet_add_money_requests
  WHERE id = p_request_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Add-money request not found');
  END IF;

  IF v_req.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Request has already been processed');
  END IF;

  SELECT * INTO v_wallet FROM public.wallets
  WHERE user_id = v_req.user_id FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO public.wallets (user_id, balance) VALUES (v_req.user_id, 0.00)
    RETURNING * INTO v_wallet;
  END IF;

  v_before := v_wallet.balance;
  v_after := v_before + v_req.amount;

  UPDATE public.wallets
  SET balance = v_after,
      total_deposited = total_deposited + v_req.amount,
      updated_at = NOW()
  WHERE id = v_wallet.id;

  INSERT INTO public.wallet_transactions (
    wallet_id, user_id, type, amount, balance_before, balance_after,
    status, payment_method, trx_id, sender_number, reference_id, note
  ) VALUES (
    v_wallet.id, v_req.user_id, 'add_money', v_req.amount, v_before, v_after,
    'completed', v_req.payment_method, v_req.trx_id, v_req.sender_number,
    p_request_id::TEXT, 'Add money approved by admin'
  ) RETURNING id INTO v_tx_id;

  UPDATE public.wallet_add_money_requests
  SET status = 'approved', approved_by = p_admin_id, approved_at = NOW(), updated_at = NOW()
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Add money approved successfully',
    'balance_after', v_after,
    'transaction_id', v_tx_id
  );
END;
$$;

-- RPC 2: wallet_p2p_transfer
CREATE OR REPLACE FUNCTION public.wallet_p2p_transfer(
  p_sender_id UUID,
  p_receiver_identifier TEXT,
  p_amount NUMERIC,
  p_note TEXT DEFAULT ''
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_sender_wallet RECORD;
  v_receiver_wallet RECORD;
  v_receiver_user_id UUID;
  v_sender_before NUMERIC;
  v_sender_after NUMERIC;
  v_receiver_before NUMERIC;
  v_receiver_after NUMERIC;
BEGIN
  IF p_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid transfer amount');
  END IF;

  IF p_receiver_identifier ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    v_receiver_user_id := p_receiver_identifier::UUID;
  ELSE
    SELECT user_id INTO v_receiver_user_id FROM public.wallets WHERE phone = p_receiver_identifier LIMIT 1;
    IF v_receiver_user_id IS NULL THEN
      SELECT id INTO v_receiver_user_id FROM auth.users WHERE phone = p_receiver_identifier OR email = p_receiver_identifier LIMIT 1;
    END IF;
  END IF;

  IF v_receiver_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'Receiver user not found');
  END IF;

  IF p_sender_id = v_receiver_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'Cannot transfer to own account');
  END IF;

  SELECT * INTO v_sender_wallet FROM public.wallets WHERE user_id = p_sender_id FOR UPDATE;
  IF NOT FOUND OR v_sender_wallet.is_frozen THEN
    RETURN jsonb_build_object('success', false, 'message', 'Sender wallet unavailable or frozen');
  END IF;

  IF v_sender_wallet.balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'message', 'Insufficient balance');
  END IF;

  SELECT * INTO v_receiver_wallet FROM public.wallets WHERE user_id = v_receiver_user_id FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO public.wallets (user_id, balance) VALUES (v_receiver_user_id, 0.00)
    RETURNING * INTO v_receiver_wallet;
  END IF;

  v_sender_before := v_sender_wallet.balance;
  v_sender_after := v_sender_before - p_amount;
  v_receiver_before := v_receiver_wallet.balance;
  v_receiver_after := v_receiver_before + p_amount;

  UPDATE public.wallets
  SET balance = v_sender_after, total_spent = total_spent + p_amount, updated_at = NOW()
  WHERE id = v_sender_wallet.id;

  UPDATE public.wallets
  SET balance = v_receiver_after, total_deposited = total_deposited + p_amount, updated_at = NOW()
  WHERE id = v_receiver_wallet.id;

  INSERT INTO public.wallet_transactions (
    wallet_id, user_id, type, amount, balance_before, balance_after,
    counterpart_user_id, note
  ) VALUES (
    v_sender_wallet.id, p_sender_id, 'transfer_out', p_amount, v_sender_before, v_sender_after,
    v_receiver_user_id, COALESCE(p_note, 'P2P Send Money')
  );

  INSERT INTO public.wallet_transactions (
    wallet_id, user_id, type, amount, balance_before, balance_after,
    counterpart_user_id, note
  ) VALUES (
    v_receiver_wallet.id, v_receiver_user_id, 'transfer_in', p_amount, v_receiver_before, v_receiver_after,
    p_sender_id, COALESCE(p_note, 'P2P Received Money')
  );

  RETURN jsonb_build_object('success', true, 'message', 'Transfer completed successfully', 'new_balance', v_sender_after);
END;
$$;

-- RPC 3: wallet_internal_purchase
CREATE OR REPLACE FUNCTION public.wallet_internal_purchase(
  p_buyer_id UUID,
  p_seller_id UUID,
  p_amount NUMERIC,
  p_order_ref TEXT,
  p_description TEXT DEFAULT ''
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_buyer_wallet RECORD;
  v_seller_wallet RECORD;
  v_before NUMERIC;
  v_after NUMERIC;
BEGIN
  IF p_amount <= 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'Invalid purchase amount');
  END IF;

  SELECT * INTO v_buyer_wallet FROM public.wallets WHERE user_id = p_buyer_id FOR UPDATE;
  IF NOT FOUND OR v_buyer_wallet.balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'message', 'Insufficient wallet balance');
  END IF;

  v_before := v_buyer_wallet.balance;
  v_after := v_before - p_amount;

  UPDATE public.wallets
  SET balance = v_after, total_spent = total_spent + p_amount, updated_at = NOW()
  WHERE id = v_buyer_wallet.id;

  INSERT INTO public.wallet_transactions (
    wallet_id, user_id, type, amount, balance_before, balance_after,
    counterpart_user_id, reference_id, note
  ) VALUES (
    v_buyer_wallet.id, p_buyer_id, 'purchase', p_amount, v_before, v_after,
    p_seller_id, p_order_ref, COALESCE(p_description, 'Order purchase payment')
  );

  IF p_seller_id IS NOT NULL AND p_seller_id != p_buyer_id THEN
    SELECT * INTO v_seller_wallet FROM public.wallets WHERE user_id = p_seller_id FOR UPDATE;
    IF NOT FOUND THEN
      INSERT INTO public.wallets (user_id, balance) VALUES (p_seller_id, 0.00)
      RETURNING * INTO v_seller_wallet;
    END IF;

    UPDATE public.wallets
    SET balance = balance + p_amount, total_earned = total_earned + p_amount, updated_at = NOW()
    WHERE id = v_seller_wallet.id;

    INSERT INTO public.wallet_transactions (
      wallet_id, user_id, type, amount, balance_before, balance_after,
      counterpart_user_id, reference_id, note
    ) VALUES (
      v_seller_wallet.id, p_seller_id, 'earning', p_amount,
      v_seller_wallet.balance, v_seller_wallet.balance + p_amount,
      p_buyer_id, p_order_ref, 'Sale revenue credited'
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'Purchase paid successfully', 'new_balance', v_after);
END;
$$;

-- RPC 4: wallet_withdrawal_approve
CREATE OR REPLACE FUNCTION public.wallet_withdrawal_approve(
  p_withdrawal_id UUID,
  p_admin_id UUID DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_w RECORD;
  v_wallet RECORD;
  v_before NUMERIC;
  v_after NUMERIC;
BEGIN
  SELECT * INTO v_w FROM public.wallet_withdrawals WHERE id = p_withdrawal_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Withdrawal request not found');
  END IF;

  IF v_w.status != 'pending' AND v_w.status != 'processing' THEN
    RETURN jsonb_build_object('success', false, 'message', 'Withdrawal already completed or rejected');
  END IF;

  SELECT * INTO v_wallet FROM public.wallets WHERE user_id = v_w.user_id FOR UPDATE;
  IF NOT FOUND OR v_wallet.balance < v_w.amount THEN
    RETURN jsonb_build_object('success', false, 'message', 'User does not have sufficient balance for withdrawal');
  END IF;

  v_before := v_wallet.balance;
  v_after := v_before - v_w.amount;

  UPDATE public.wallets
  SET balance = v_after, total_withdrawn = total_withdrawn + v_w.amount, updated_at = NOW()
  WHERE id = v_wallet.id;

  INSERT INTO public.wallet_transactions (
    wallet_id, user_id, type, amount, balance_before, balance_after,
    payment_method, receiver_number, reference_id, note
  ) VALUES (
    v_wallet.id, v_w.user_id, 'withdrawal', v_w.amount, v_before, v_after,
    v_w.payout_method, v_w.payout_number, p_withdrawal_id::TEXT, 'Cashout completed'
  );

  UPDATE public.wallet_withdrawals
  SET status = 'approved', processed_by = p_admin_id, processed_at = NOW(), updated_at = NOW()
  WHERE id = p_withdrawal_id;

  RETURN jsonb_build_object('success', true, 'message', 'Withdrawal approved', 'new_balance', v_after);
END;
$$;

-- Wallets RLS
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_add_money_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_withdrawals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own wallet" ON public.wallets FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can view own transactions" ON public.wallet_transactions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can view own add money requests" ON public.wallet_add_money_requests FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create add money requests" ON public.wallet_add_money_requests FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can view own withdrawals" ON public.wallet_withdrawals FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can create withdrawals" ON public.wallet_withdrawals FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Centralized Dynamic Form Categories
CREATE TABLE IF NOT EXISTS public.form_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  form_type TEXT NOT NULL CHECK (form_type IN ('merchant', 'stock', 'bhogyoponno')),
  category_name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT form_categories_type_name_unique UNIQUE (form_type, category_name)
);

ALTER TABLE public.form_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public read access for form_categories" ON public.form_categories FOR SELECT USING (true);
CREATE POLICY "Allow insert for form_categories" ON public.form_categories FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow update for form_categories" ON public.form_categories FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "Allow delete for form_categories" ON public.form_categories FOR DELETE USING (true);
GRANT ALL ON TABLE public.form_categories TO anon, authenticated, service_role;
CREATE INDEX IF NOT EXISTS idx_form_categories_form_type ON public.form_categories(form_type);
