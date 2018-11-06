# frozen_string_literal: true

require_dependency 'gitlab/email/handler'

# Inspired in great part by Discourse's Email::Receiver
module Gitlab
  module Email
    ProcessingError = Class.new(StandardError)
    EmailUnparsableError = Class.new(ProcessingError)
    SentNotificationNotFoundError = Class.new(ProcessingError)
    ProjectNotFound = Class.new(ProcessingError)
    EmptyEmailError = Class.new(ProcessingError)
    AutoGeneratedEmailError = Class.new(ProcessingError)
    UserNotFoundError = Class.new(ProcessingError)
    UserBlockedError = Class.new(ProcessingError)
    UserNotAuthorizedError = Class.new(ProcessingError)
    NoteableNotFoundError = Class.new(ProcessingError)
    InvalidRecordError = Class.new(ProcessingError)
    InvalidNoteError = Class.new(InvalidRecordError)
    InvalidIssueError = Class.new(InvalidRecordError)
    InvalidMergeRequestError = Class.new(InvalidRecordError)
    UnknownIncomingEmail = Class.new(ProcessingError)

    class Receiver
      def initialize(raw)
        @raw = raw
      end

      def execute
        raise EmptyEmailError if @raw.blank?

        mail = build_mail

        ignore_auto_submitted!(mail)

        mail_key = extract_mail_key(mail)
        handler = Handler.for(mail, mail_key)

        raise UnknownIncomingEmail unless handler

        Gitlab::Metrics.add_event(:receive_email, handler.metrics_params)

        handler.execute
      end

      private

      def build_mail
        Mail::Message.new(@raw)
      rescue Encoding::UndefinedConversionError,
             Encoding::InvalidByteSequenceError => e
        raise EmailUnparsableError, e
      end

      def extract_mail_key(mail)
        key_from_to_header(mail) || key_from_additional_headers(mail)
      end

      def key_from_to_header(mail)
        mail.to.find do |address|
          key = Gitlab::IncomingEmail.key_from_address(address)
          break key if key
        end
      end

      def key_from_additional_headers(mail)
        find_key_from_references(mail) ||
          find_key_from_delivered_to_header(mail)
      end

      def ensure_references_array(references)
        case references
        when Array
          references
        when String
          # Handle emails from clients which append with commas,
          # example clients are Microsoft exchange and iOS app
          Gitlab::IncomingEmail.scan_fallback_references(references)
        when nil
          []
        end
      end

      def find_key_from_references(mail)
        ensure_references_array(mail.references).find do |mail_id|
          key = Gitlab::IncomingEmail.key_from_fallback_message_id(mail_id)
          break key if key
        end
      end

      def find_key_from_delivered_to_header(mail)
        Array(mail[:delivered_to]).find do |header|
          key = Gitlab::IncomingEmail.key_from_address(header.value)
          break key if key
        end
      end

      def ignore_auto_submitted!(mail)
        # Mail::Header#[] is case-insensitive
        auto_submitted = mail.header['Auto-Submitted']&.value

        # Mail::Field#value would strip leading and trailing whitespace
        raise AutoGeneratedEmailError if
          # See also https://tools.ietf.org/html/rfc3834
          auto_submitted && auto_submitted != 'no'
      end
    end
  end
end
