from datetime import datetime
from pathlib import Path
import time

from selenium.common.exceptions import TimeoutException
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium import webdriver
from tqdm import tqdm
import pandas as pd
import yaml

# -----------------

REPO_ROOT = Path(__file__).resolve().parents[2]
with open(REPO_ROOT / "pipeline" / "configs" / "config.yaml") as f:
    cfg = yaml.safe_load(f)

# Configs: Inquirer
INQUIRER_SEARCH_PAGE_BASE_URL = cfg.get("rainfall", {}).get("inquirer", {}).get("search_page_base_url")
INQUIRER_PAGES_DELAY = cfg.get("rainfall", {}).get("inquirer", {}).get("pages_delay", 2)
ARTICLE_LOAD_DELAY = cfg.get("rainfall", {}).get("inquirer", {}).get("article_load_delay", 1.5)

# Configs: AOI
AOI_AREA_NAME = cfg.get("aoi", {}).get("area_name", "")

# -----------------

def fetch_inquirer_list_flooded_articles(
    delay_between_search_pages: float = INQUIRER_PAGES_DELAY,
    delay_per_article: float =ARTICLE_LOAD_DELAY,
    max_pages: int = 10,
    headless: bool = True
) -> pd.DataFrame:
    
    options = Options()
    if headless:
        options.add_argument("--headless=new")
    options.add_argument("--window-size=1920,1080")
    options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36")


    # ---------------------------
    #  SEARCH PAGE SCRAPING
    # ---------------------------

    search_page_driver = webdriver.Chrome(options=options)
    collected = []
    page = 1
    try:
        print("📰 Crawling Inquirer search results (Flooded roads)...")
        while page <= max_pages:
            url = INQUIRER_SEARCH_PAGE_BASE_URL + str(page)
            search_page_driver.get(url)
            time.sleep(delay_per_article)

            news_items = search_page_driver.find_elements(By.CSS_SELECTOR, "div.gsc-webResult.gsc-result")
            if not news_items:
                news_items = search_page_driver.find_elements(By.CSS_SELECTOR, "div.gsc-result-wrapper")
            if not news_items:
                print(f"ℹ️ No results on page {page}; stopping.")
                break

            print(f"🔎 Page {page}: {len(news_items)} items")
            for item in news_items:
                try:
                    a = item.find_element(By.CSS_SELECTOR, "a.gs-title")
                    title = a.text.strip()
                    link = a.get_attribute("href")
                    if link and not any(d["link"] == link for d in collected):
                        collected.append({"title": title, "link": link})
                except Exception:
                    continue

            page += 1
        print(f"🛑 Stopped after page {page-1}")
    finally:
        search_page_driver.quit()

    print(f"🔎 Total article links: {len(collected)}")
    if not collected:
        return pd.DataFrame(columns=["title", "date", "link", "article_text"])

    # ---------------------------
    #  ARTICLE SCRAPING
    # ---------------------------

    print("📝 Fetching article bodies and dates…")

    article_driver = webdriver.Chrome(options=options)
    wait = WebDriverWait(article_driver, 30)
    target = AOI_AREA_NAME.strip().lower()
    rows = []

    for i, item in enumerate(tqdm(collected, desc="📖 Parsing article pages", unit="article")):
        link = item.get("link", "")
        title = item.get("title", "")

        # print(f"\n\n> Link: {link}\n> Title: {title}\n")
        
        article_driver.get(link)
        time.sleep(delay_between_search_pages)

        # Fetch article publish datetime
        datetime_meta = wait.until(EC.presence_of_element_located(
            (By.CSS_SELECTOR, "meta[property='article:published_time']")
        ))

        date = datetime_meta.get_attribute("content")
        date = datetime.strptime(date.rsplit(" ", 1)[0], "%a, %d %b %Y %H:%M:%S")
        date = date.strftime("%d %b %Y") # Sample: 02 Sep 2025

        # Fetch base wrapper element
        wrapper = wait.until(EC.presence_of_element_located(
            (By.XPATH, "//div[@id='art_body_wrap']")
        ))

        # If the AOI is detected as one of the reported city/municipality
        try:
            aoi_p = WebDriverWait(wrapper, delay_per_article).until(EC.presence_of_element_located(
                (By.XPATH, f"//p[@dir='ltr' and contains(translate(normalize-space(.), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz'),'{target}')]")
            ))
            ul = aoi_p.find_element(By.XPATH, "following-sibling::ul[1]")
            affected_areas = ul.find_elements(By.CSS_SELECTOR, "li[dir='ltr']")
            affected_areas = [p.text.strip() for p in affected_areas]

            # Create a new record on the articles df
            rows.append({
                "id": i,
                "title": title,
                "link": link,
                "date": date,
                "affected_areas": affected_areas
            })
            
        except TimeoutException:
            # print(f"> [!] '{AOI_AREA_NAME}' not listed under this article.\n")
            pass

    article_driver.quit()
    articles_df = pd.DataFrame(rows, columns=["id", "title", "link", "date", "affected_areas"])
    return articles_df

if __name__ == "__main__":
    articles_df = fetch_inquirer_list_flooded_articles(
        delay_between_search_pages=INQUIRER_PAGES_DELAY,
        delay_per_article=ARTICLE_LOAD_DELAY,
        #max_pages=2,
        headless=True
    )