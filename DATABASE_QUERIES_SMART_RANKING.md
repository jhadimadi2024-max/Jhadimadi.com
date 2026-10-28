# Multi-Merchant Search Diversity & Smart Product Ranking Engine

This document details the database queries, mathematical ranking formulas, and backend sorting logic for **Search Results Diversity** and **Smart Product Ranking** on Jhadimadi.com.

---

## 1. Core Architecture & Requirements

When a customer searches for a product (e.g., `'shoes'`, `'শুটকি'`, `'মরিচ'`, `'চাকমা পোশাক'`):
1. **Search Diversity**: Interleaves products from different merchants in round-robin fashion with a configurable `maxConsecutivePerMerchant` (default: 1) so no single merchant dominates the top search results.
2. **Smart Ranking Score (0 - 100 Points)**:
   - **Stock Status**: In-stock products strictly appear on top; out-of-stock items (`stock_quantity <= 0`, `is_out_of_stock = true`, or `status = 'Stock Out'`) are hidden from search results.
   - **Product Ratings & Reviews (0 - 25 pts)**: Bayesian-weighted rating formula that accounts for both average stars and volume of reviews to prevent 1-review 5-star items from outranking proven products.
   - **Sales History & Best Sellers (0 - 20 pts)**: Logarithmic curve on units sold (`sales_count`) with an extra bonus for verified `is_best_seller` / `badge = 'বেস্ট সেলার'`.
   - **Merchant Delivery Speed (0 - 15 pts)**: Faster delivery time yields a higher boost (Same-day/24h: +15 pts, 2-day: +12.75 pts, 3-day: +9 pts, 5+ days: +1.5 pts).
   - **Search Query Relevance (0 - 40 pts)**: Exact matches, prefix matches, token-level matching across Bengali and English, categories, and tags.

---

## 2. PostgreSQL / Supabase Database Queries

### 2.1 Complete SQL Query with Smart Ranking & Multi-Merchant Diversity Interleaving (Window Functions)

This SQL query calculates the smart ranking score directly inside PostgreSQL and uses `ROW_NUMBER() OVER (PARTITION BY merchant_id ...)` to interleave results across different merchants:

```sql
-- Parameterized Search: :search_query = 'shoes', :category = NULL, :limit = 20, :max_per_merchant = 1

WITH candidate_products AS (
    SELECT 
        p.id,
        p.code,
        p.name_bn,
        p.name_en,
        p.category,
        p.category_label_bn,
        p.price,
        p.image_url,
        COALESCE(p.stock_quantity, p.stock, 0) AS stock_quantity,
        COALESCE(p.avg_rating, p.rating, 0.0)::FLOAT AS rating,
        COALESCE(p.reviews_count, 0)::INT AS reviews_count,
        COALESCE(p.sales_count, 0)::INT AS sales_count,
        COALESCE(p.is_best_seller, FALSE) AS is_best_seller,
        COALESCE(p.delivery_days, 3)::FLOAT AS delivery_days,
        -- Resolved Merchant ID:
        COALESCE(
            NULLIF(TRIM(p.seller_id), ''), 
            NULLIF(TRIM(p.seller_unique_id), ''), 
            NULLIF(TRIM(p.merchant_id), ''), 
            'jhadimadi_official'
        ) AS merchant_id,
        COALESCE(p.shop_name, p.seller_name, 'ঝাদিমাদি অফিসিয়াল স্টোর') AS merchant_name,
        
        -- 1. Relevance Score (0 - 40)
        CASE 
            WHEN LOWER(p.name_bn) = LOWER(:search_query) OR LOWER(p.name_en) = LOWER(:search_query) THEN 40.0
            WHEN LOWER(p.name_bn) LIKE LOWER(:search_query || '%') OR LOWER(p.name_en) LIKE LOWER(:search_query || '%') THEN 36.0
            WHEN LOWER(p.name_bn) LIKE LOWER('%' || :search_query || '%') OR LOWER(p.name_en) LIKE LOWER('%' || :search_query || '%') THEN 32.0
            WHEN LOWER(p.category) LIKE LOWER('%' || :search_query || '%') THEN 20.0
            ELSE 10.0
        END AS relevance_score,

        -- 2. Bayesian Weighted Rating Score (0 - 25)
        -- Bayesian Formula: (reviews * rating + 3 * 3.8) / (reviews + 3) scaled to 25 pts
        ROUND(
            (
                (COALESCE(p.reviews_count, 0) * LEAST(5.0, GREATEST(0.0, COALESCE(p.avg_rating, p.rating, 0.0))) + 3 * 3.8) 
                / (COALESCE(p.reviews_count, 0) + 3)
            ) / 5.0 * 25.0 * (0.75 + 0.25 * LEAST(1.0, COALESCE(p.reviews_count, 0) / 30.0))
        , 2) AS rating_score,

        -- 3. Sales History & Best Seller Score (0 - 20)
        -- Logarithmic curve: LOG10(sales + 1) / 2.0 scaled to 20 pts + bonus
        ROUND(
            LEAST(20.0, 
                (LEAST(1.0, LOG(COALESCE(p.sales_count, 0) + 1) / 2.0) * 0.75 + 
                 CASE WHEN p.is_best_seller = TRUE OR p.badge = 'বেস্ট সেলার' THEN 0.25 ELSE 0.0 END
                ) * 20.0
            )
        , 2) AS sales_score,

        -- 4. Merchant Delivery Speed Boost (0 - 15)
        -- Faster delivery = higher boost
        CASE 
            WHEN COALESCE(p.delivery_days, 3) <= 1 THEN 15.0  -- Same day / 24h
            WHEN COALESCE(p.delivery_days, 3) <= 2 THEN 12.75 -- 2-day delivery
            WHEN COALESCE(p.delivery_days, 3) <= 3 THEN 9.0   -- 3-day delivery
            WHEN COALESCE(p.delivery_days, 3) <= 4 THEN 6.0   -- 4-day delivery
            WHEN COALESCE(p.delivery_days, 3) <= 5 THEN 3.75  -- 5-day delivery
            ELSE 1.5                                          -- Standard / slow courier
        END AS delivery_speed_score

    FROM products p
    WHERE 
        -- RULE 1: STRICT IN-STOCK FILTER (Out-of-stock items hidden)
        COALESCE(p.stock_quantity, p.stock, 0) > 0
        AND p.status NOT IN ('Stock Out', 'out_of_stock', 'deleted')
        AND (p.is_out_of_stock IS NULL OR p.is_out_of_stock = FALSE)
        AND (p.is_published IS NULL OR p.is_published = TRUE)
        AND (
            LOWER(p.name_bn) LIKE LOWER('%' || :search_query || '%')
            OR LOWER(p.name_en) LIKE LOWER('%' || :search_query || '%')
            OR LOWER(p.category) LIKE LOWER('%' || :search_query || '%')
            OR LOWER(p.description_bn) LIKE LOWER('%' || :search_query || '%')
        )
),

scored_products AS (
    SELECT 
        *,
        ROUND(relevance_score + rating_score + sales_score + delivery_speed_score, 1) AS smart_ranking_score,
        -- Intra-merchant rank: Rank products of the SAME merchant by their individual smart score
        ROW_NUMBER() OVER (
            PARTITION BY merchant_id 
            ORDER BY (relevance_score + rating_score + sales_score + delivery_speed_score) DESC
        ) AS merchant_product_rank
    FROM candidate_products
),

interleaved_diversity_results AS (
    SELECT 
        *,
        -- Merchant priority: Rank merchants by their single best-scoring product
        DENSE_RANK() OVER (
            ORDER BY MAX(smart_ranking_score) OVER (PARTITION BY merchant_id) DESC, merchant_id
        ) AS merchant_tier_order
    FROM scored_products
)

-- Final Diversity Output:
-- Sorted by merchant_product_rank first (interleaving Round 1, Round 2, ...),
-- and within each round ordered by merchant tier order.
SELECT 
    id,
    code,
    name_bn,
    name_en,
    category,
    price,
    stock_quantity,
    rating,
    reviews_count,
    sales_count,
    delivery_days,
    merchant_id,
    merchant_name,
    smart_ranking_score,
    relevance_score,
    rating_score,
    sales_score,
    delivery_speed_score,
    merchant_product_rank AS round_number
FROM interleaved_diversity_results
ORDER BY 
    merchant_product_rank ASC,     -- Round-robin interleaving across merchants!
    smart_ranking_score DESC       -- Highest score within the round
LIMIT :limit;
```

---

### 2.2 Recommended Database Indexes for High-Performance Queries

To ensure sub-10ms search queries under heavy e-commerce load:

```sql
-- 1. Full-text search and Trigram Index for fast fuzzy & Bengali string matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS idx_products_search_trgm 
ON products USING gin (name_bn gin_trgm_ops, name_en gin_trgm_ops, category gin_trgm_ops);

-- 2. Stock filtering index (instant WHERE stock_quantity > 0)
CREATE INDEX IF NOT EXISTS idx_products_stock_active 
ON products (stock_quantity) 
WHERE stock_quantity > 0 AND status != 'deleted';

-- 3. Composite Merchant & Ranking Metric Index
CREATE INDEX IF NOT EXISTS idx_products_merchant_smart_ranking 
ON products (seller_id, sales_count DESC, avg_rating DESC, delivery_days ASC);
```

---

### 2.3 Supabase JavaScript Client Query

```typescript
import { supabase } from './supabaseClient';
import { filterAndRankDiverseProducts } from '../utils/searchDiversityEngine';

export async function searchDiverseProducts(query: string, limit = 20) {
  // Step 1: Query Supabase with in-stock filter
  const { data: candidates, error } = await supabase
    .from('products')
    .select('*')
    .gt('stock_quantity', 0)
    .or(`name_bn.ilike.%${query}%,name_en.ilike.%${query}%,category.ilike.%${query}%`)
    .limit(limit * 3); // Fetch candidate pool for fair interleaving

  if (error || !candidates) return [];

  // Step 2: Apply Smart Ranking Score & Merchant Interleaving
  const { items, breakdowns, totalMerchants } = filterAndRankDiverseProducts(candidates, query, {
    hideOutOfStock: true,
    maxConsecutivePerMerchant: 1 // No merchant can take consecutive top slots
  });

  return items.slice(0, limit);
}
```

---

## 3. Backend REST API Endpoints

### 1. `GET /api/search/products`
Dedicated endpoint returning diversified products and score breakdowns:
- **Query Params**:
  - `q`: Search keyword (e.g., `'shoes'`, `'শুটকি'`)
  - `category`: Optional category filter
  - `limit`: Number of results (default 20, max 100)
  - `maxPerMerchant`: Max consecutive products per merchant (default 1)
  - `hideOutOfStock`: Boolean (default true)
- **Response Structure**:
```json
{
  "success": true,
  "query": "shoes",
  "totalCount": 8,
  "totalMerchants": 4,
  "diversity": {
    "applied": true,
    "maxConsecutivePerMerchant": 1,
    "uniqueMerchantsInTopResults": 4
  },
  "rankingWeights": {
    "relevanceMax": 40,
    "ratingMax": 25,
    "salesMax": 20,
    "deliverySpeedMax": 15,
    "outOfStockRule": "strictly hidden"
  },
  "products": [
    {
      "id": "prod_1",
      "name_bn": "লেদার স্নিকার জুতা",
      "shop_name": "সীমা হাব",
      "_smartRanking": {
        "relevanceScore": 36.0,
        "ratingScore": 22.4,
        "salesScore": 17.5,
        "deliverySpeedScore": 12.75,
        "totalScore": 88.65,
        "merchantId": "PS-4400-003",
        "merchantName": "সীমা হাব",
        "deliveryDays": 2,
        "isInStock": true
      }
    },
    {
      "id": "prod_2",
      "name_bn": "হিল স্নিকার জুতো",
      "shop_name": "আলিয়া বুটিকস",
      "_smartRanking": {
        "relevanceScore": 34.0,
        "ratingScore": 21.0,
        "salesScore": 16.0,
        "deliverySpeedScore": 15.0,
        "totalScore": 86.0,
        "merchantId": "PS-4500-002",
        "merchantName": "আলিয়া বুটিকস",
        "deliveryDays": 1,
        "isInStock": true
      }
    }
  ]
}
```

### 2. `GET /api/search/global`
The unified search endpoint (`products`, `serviceProviders`, `bloodDonors`, `jobCirculars`, `jobSeekers`) also uses `filterAndRankDiverseProducts` for the `products` list, ensuring all global searches benefit from smart ranking and multi-merchant diversity interleaving.
