# encoding: utf-8
# bundle exec rake crawler:process
require 'capybara'
require 'capybara/poltergeist'
require 'selenium-webdriver'
require 'capybara/dsl'
require 'google_drive'
require 'date'

module CrawlerTask
  extend Rake::DSL
  extend self

  # set driver
  Capybara.current_driver = :selenium
  @googleSession = GoogleDrive::Session.from_config("config.json")
  @sp = @googleSession.spreadsheet_by_url("https://docs.google.com/spreadsheets/d/1iMsDc3QoaQZbCv3BhOeF9ksFgOPOXr9meYEuWV5vN5c/edit#gid=1069768647")

  namespace :crawler do
    desc "googleへクローリングを実行します" #=> 説明
    def logger
      sleep 30
      Rails.logger
    end

    def create_file_name totalCount, keyword, key
      '%d_%s_%s_screenshot.png' % [totalCount, key, keyword.gsub("allintitle:","").gsub(" ","").gsub('"', "")]
    end

    def create_file_path totalCount, keyword, key
      'tmp/%d_%s_%s_screenshot.png' % [totalCount, key, keyword.gsub("allintitle:","").gsub(" ","").gsub('"', "")]
    end

    def save_page session, totalCount, limit, keyword, key
      session.all(:xpath, '//*[@class="fl"]').each do | v |
        if totalCount > limit && v.text.eql?(key)
          href = v["href"]
          session.visit href
          logger.info href
          session.save_screenshot(create_file_path(totalCount, keyword, key), full: true)
          break
        end
      end
      session
    end

    def crawler_process session, targets
      compWord = ""
      targets.each do | target |
        if compWord.blank?
          compWord = 'allintitle:%s' % target
        else
          compWord = '"%s" "%s"' % [compWord, target]
        end
        patrol_risk session, compWord
      end
    end

    def patrol_risk session, compWord
      Require.find_in_batches(batch_size: 16) do |require_array|
        requireWord = ""
        for var in require_array do
          if requireWord.blank?
            requireWord = '"%s"' % var["word"]
          else
            requireWord = '%s OR "%s"' % [requireWord, var["word"]]
          end
        end
        keyword = compWord + " " + requireWord

        # start crawling
        url = "https://www.google.co.jp/search?q=" + keyword
        session.visit URI.escape(url)
        logger.info url

        result_status = session.all("#resultStats")[0]
        count = (result_status.blank?) ? 0 : result_status.text.gsub(/[^\d]/, "").to_i

        # save image
        session.save_screenshot(create_file_path(count, keyword, "1"), full: true)
        createFileName = create_file_name(count, keyword, "1")
        @googleSession.upload_from_file(create_file_path(count, keyword, "1"), createFileName, convert: false)
      end # Require
    end

    task :process => :environment do
      # create capybara session
      session = Capybara::Session.new(:poltergeist)
      ws = @sp.worksheet_by_title("list")
      now = DateTime.now.strftime("%Y年%m月%d日 %H:%M:%S")
      ws[1, 2] = now # B1
      ws[1, 3] = "!!!!!!!!!!実行中!!!!!!!!!!" # C1
      ws.save
      rowNumMax = ws.num_rows
      if 3 >= rowNumMax
        ws[1, 3] = "実行完了" # C1
        exit!
      end
      for row in 3..rowNumMax do
        company_name = ws[row, 2] #B get company_name
        owner = ws[row, 3] #C get owner
        compFlg = ws[row, 4] #D get date
        ownFlg = ws[row, 5] #D get date
        processFlg = false
        if compFlg.blank? && company_name.present?
          crawler_process session, [company_name]
          ws[row, 4] = DateTime.now.strftime("%Y年%m月%d日 %H:%M:%S")
          processFlg = true
        end
        if ownFlg.blank? && owner.present?
          crawler_process session, [owner]
          ws[row, 5] = DateTime.now.strftime("%Y年%m月%d日 %H:%M:%S")
          processFlg = true
        end

        if processFlg
          break
        else
          next
        end
      end

      now = DateTime.now.strftime("%Y年%m月%d日 %H:%M:%S")
      ws[1, 2] = now # B1
      ws[1, 3] = "実行完了" # C1
      ws.save
      #break
    end # process

  end # crawler

end # Module
