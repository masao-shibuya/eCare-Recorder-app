//
//  ViewController.swift
//  eCare Recorder
//
//  Created by 渋谷正男 on 2018/12/15.
//  Copyright © 2018年 cardguard jp. All rights reserved.
//
//  Special thanks to :
//  https://github.com/wuqiong/mp3lame-for-iOS


import UIKit
import AVFoundation
import AudioToolbox
import MessageUI


class ViewController: UIViewController, AVAudioRecorderDelegate, MFMailComposeViewControllerDelegate, XMLParserDelegate {

    var audioRecorder: AVAudioRecorder?
    var meterTimer: Timer?
    var progressTime: Timer?
    var progressStartTime: Date?
    
    var filePaths:[URL]?
    var documentDir:URL?
    var isMP3Active:Bool?
    
    let defaultAddress = "<default-mail-address>"
    var email:String?
    
    @IBOutlet weak var levelMeter: UIProgressView!
    @IBOutlet weak var recording_view: UIView!
    @IBOutlet weak var progress_time: UILabel!
    @IBOutlet weak var progress_meter: UIProgressView!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // ビュー背景を設定
        let backgroundImag = UIImage(named: "bg.png")
        self.view.backgroundColor = UIColor(patternImage: backgroundImag!);
        
        self.filePaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        self.documentDir = filePaths?[0]
        
        /// 録音可能カテゴリに設定する
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode:.default, options: [])
        } catch  {
            // エラー処理
            fatalError("カテゴリ設定失敗")
        }
        
        // sessionのアクティブ化
        do {
            try session.setActive(true)
        } catch {
            // audio session有効化失敗時の処理
            // (ここではエラーとして停止している）
            fatalError("session有効化失敗")
        }
        
        getMailAddress()
        setupAudioRecorder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        meterTimer?.invalidate()
        progressTime?.invalidate()
    }

    @IBAction func actionStart(_ sender: Any) {
        audioRecorder!.stop()
        audioRecorder!.prepareToRecord()
        // 30秒録音して終了
        audioRecorder!.record(forDuration: 30.0)
        audioRecorder!.record()
        progressTime = Timer.scheduledTimer(timeInterval: 0.2, target:self, selector:#selector(progressCallBack),
                                                             userInfo:nil, repeats:true);
        progressStartTime = Date()
    }
    
    @IBAction func actionStop(_ sender: Any) {
    }
    
    
    @objc func progressCallBack(timer: Timer) {
        let second = 30 - Date().timeIntervalSince(progressStartTime!)
        
        self.progress_time.text = String.init(format: "%@%@","00 : ", String.init(format:"%02d", Int(second)))
        self.progress_meter.progress = Float(Date().timeIntervalSince(progressStartTime!) / 30.0)
        if second < 0 {
            progressTime!.invalidate()
            self.recording_view.isHidden = true
            
            DispatchQueue(label: "<bundle id>.mp3queue").async {
                self.toMp3()
                // メインスレッドで実行
                DispatchQueue.main.async {
                    self.displayComposerSheet()
                }
            }
        } else {
            self.recording_view.isHidden = false
        }
    }
    
    func getMailAddress() {
        let url = NSURL(string:"https://<xml-server>")
        if let data = try? NSData(contentsOf:url! as URL, options:NSData.ReadingOptions.uncached) {
            if let strXml = String(data:data as Data, encoding:.utf8) {
                if let doc = try? XMLDocument(string: strXml) {
                    if let root = doc.root {        //  現状のXMLの形式では最初の一つしか取れません。XMLには階層構造が必要です。
                        email = root.stringValue
                    }
                }
            }
        }
        
        if email == nil {
            print("email from server was null")
            email = defaultAddress
        }
    }
    
    
    func setupAudioRecorder() {
        
        // 録音用URLを設定
        let dirURL = documentsDirectoryURL()
        let fileName = "<foo>.caf"
        let recordingsURL = dirURL.appendingPathComponent(fileName)
        
        // 録音設定
        let recordSettings:[String: Any] =
            [AVFormatIDKey: Int(kAudioFormatLinearPCM),
             AVNumberOfChannelsKey: 1,
             AVLinearPCMBitDepthKey: 16,
             AVLinearPCMIsBigEndianKey: false,
             AVLinearPCMIsFloatKey: false,
             AVSampleRateKey: 16000]
        do {
            audioRecorder = try AVAudioRecorder(url: recordingsURL!, settings: recordSettings)
        } catch {
            audioRecorder = nil
            return
        }
        
        //  音量情報取得
        audioRecorder?.isMeteringEnabled = true
        audioRecorder?.delegate = self
        
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true, block: {(timer) in
            self.audioRecorder!.updateMeters()
            self.levelMeter.progress = pow(10, (0.02 * self.audioRecorder!.averagePower(forChannel: 0)))
            })
    }
    
    /// DocumentsのURLを取得
    func documentsDirectoryURL() -> NSURL {
        let urls = FileManager.default.urls(for: FileManager.SearchPathDirectory.documentDirectory, in: FileManager.SearchPathDomainMask.userDomainMask)
        
        if urls.isEmpty {
            fatalError("URLs for directory are empty.")
        }
        
        return urls[0] as NSURL
    }

    //  MP3へ返還
    //
    @objc func toMp3() {
        let cafFilePath = documentDir!.appendingPathComponent("<foo>.caf")
        let mp3FilePath = documentDir!.appendingPathComponent("<foo>.mp3")
        
        var read:Int
        var write:Int
        
        let pcm = InputStream(url: cafFilePath)
        let mp3 = OutputStream(url: mp3FilePath, append: false)
        
        pcm?.open()
        mp3?.open()
        
        let PCM_LENGTH: Int = 8192
        let PCM_SIZE: Int   = PCM_LENGTH * 2
        let MP3_LENGTH: Int32 = 8192
        
        let pcmBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(PCM_LENGTH))
        let tare = UnsafeMutableRawPointer(pcmBuffer)
        let pcmU8Buffer = tare.bindMemory(to: UInt8.self, capacity: PCM_SIZE)
        let mp3Buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(MP3_LENGTH))
        
        let lame = lame_init();
        lame_set_mode(lame, MONO);
        lame_set_in_samplerate(lame, 16000);
        lame_set_num_channels(lame, 1);
        lame_set_VBR(lame, vbr_default);
        lame_init_params(lame);
        
        read = (pcm?.read(pcmU8Buffer, maxLength: 2*1024))!
        repeat {
            read = (pcm?.read(pcmU8Buffer, maxLength: PCM_SIZE))! / 2
            if read == 0 {
                write = Int(lame_encode_flush(lame, mp3Buffer, Int32(MP3_LENGTH)))
            }
            else {
                write = Int(lame_encode_buffer(lame, pcmBuffer, nil, Int32(read), mp3Buffer, MP3_LENGTH))
            }
            let written = mp3?.write(mp3Buffer, maxLength: Int(write))

        } while (read != 0)
        
        lame_close(lame)
        mp3?.close()
        pcm?.close()
    }
    
    
    //  メール送信
    //  オリジナル版のobj-cから移植
    //
    func displayComposerSheet() {
        //   メール作成
        if !MFMailComposeViewController.canSendMail() {
            let msg = NSLocalizedString("mail_allow", comment: "")
            showError(message: msg)
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "YYMMddHHmmss"
        let dateStr = formatter.string(from: Date())
        
        let mp3Path = self.documentDir!.appendingPathComponent("<foo>.mp3")

        
        let picker = MFMailComposeViewController()
        picker.mailComposeDelegate = self
        picker.setSubject(String.localizedStringWithFormat("EcgMail %@", dateStr))
        
        var email_to = email
        if email_to == "" {
            email_to = defaultAddress
        }
        
        picker.setToRecipients([email_to!])
        
        //  mp3
        guard let myData = try? Data.init(contentsOf: mp3Path) else {
            showError(message: "displayComposerSheet : no data")
            return
        }
        
        let mp3filename = String.localizedStringWithFormat("%@.mp3", dateStr)
        picker.addAttachmentData(myData, mimeType: "audio/mp3", fileName: mp3filename)
        
        //  メール本文
        let emailBody = "email from iOS"
        picker.setMessageBody(emailBody, isHTML: true)
        
        //  メール編集画面を表示
        self.present(picker, animated: true, completion: nil)
    }
    
    
    func mailComposeController(_ controller: MFMailComposeViewController,
                               didFinishWith result: MFMailComposeResult, error: Error?) {
        
        controller.dismiss(animated: true, completion: nil)
        
        var msg:String
        if result == MFMailComposeResult.sent {
            msg = NSLocalizedString("mail_ok", comment: "")
        } else {
            msg = NSLocalizedString("mail_ng", comment: "")
        }
        
        let alert = UIAlertController(title: nil, message: msg, preferredStyle: UIAlertController.Style.alert)
        let defaultAction: UIAlertAction = UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler:{
            (action: UIAlertAction!) -> Void in
            exit(0)
        })
        alert.addAction(defaultAction)
        present(alert, animated:true, completion: nil)
    }
    
    func finishButton() {
    }
    
    //  エラーアラート（デバッグ用）
    func showError(message: String) {
        let alert = UIAlertController(title: "error", message: message, preferredStyle: UIAlertController.Style.alert)
        let okayButton = UIAlertAction(title: "OK", style: UIAlertAction.Style.cancel, handler: nil)
        alert.addAction(okayButton)
        
        present(alert, animated: true, completion: nil)
    }
}

