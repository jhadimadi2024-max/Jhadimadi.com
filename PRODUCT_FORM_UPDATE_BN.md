# Product Add Studio — UI/UX Update

ড্যাশবোর্ডের Add Product অংশকে আলাদা, পরিষ্কার ও professional product-entry page হিসেবে পুনর্গঠন করা হয়েছে।

## নতুন ফিচার
- বাংলা ও ইংরেজি product name
- Auto Product ID: 001, 002, 003...
- Auto SKU: JDM-001, JDM-002...
- Existing PRODUCT_CATEGORIES থেকে category নির্বাচন
- Sales price, MRP/original price, stock
- Preset unit/pack options: পিস, গ্রাম, কেজি, লিটার, প্যাকেট
- সর্বোচ্চ ৪টি product image
- প্রথম image primary image হিসেবে ব্যবহৃত
- YouTube URL
- সংক্ষিপ্ত description, badge এবং key features
- Live customer-facing preview
- Required-field validation
- Existing DataContext add/update product flow ব্যবহার করা হয়েছে
- Publish action-এ isPublished=true

## UX লক্ষ্য
অতিরিক্ত ফিল্ড না বাড়িয়ে মূল তথ্যগুলো এক জায়গায় রাখা হয়েছে। Desktop-এ form + sticky preview এবং mobile-এ responsive single-column layout ব্যবহার করা হয়েছে।

## সর্বশেষ মূল্য/অফার আপডেট
- পণ্য পরিমাণের অপশন এখন ১/২/৩/৪ পিস, ২০০/২৫০/৩০০/৪০০/৫০০ গ্রাম, ১/২/৩/৪ কেজি, ১/২/৩/৪ লিটার এবং ১/২/৩/৪ প্যাকেট।
- "অফার আছে" নামে একটি ঐচ্ছিক toggle যোগ করা হয়েছে। অফার বন্ধ থাকলে discount field দেখায় না এবং discount বাধ্যতামূলক নয়।
- অফার চালু করলে শুধু Discount (%) লিখলেই Offer Price স্বয়ংক্রিয়ভাবে হিসাব হয়। উদাহরণ: নিয়মিত মূল্য ৳৮৫০, ডিসকাউন্ট ১০% → অফার মূল্য ৳৭৬৫।
- অফার চালু থাকলে database payload-এ regular_price এবং discount_price দুটোই সংরক্ষণ করা হয়।
- Product Serial ID UI-তে JDM-001, JDM-002… ধরনের পরবর্তী ক্রমিক দেখানো হয়।
