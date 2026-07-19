# One place for the "is this uploaded file acceptable?" rule, shared by every
# endpoint that takes a file — post images, post video, profile avatar.
#
# The content type is sniffed from the bytes (Marcel) rather than trusted from
# the client-declared type; that is the security-relevant part, and it is why
# this lives in one method instead of being repeated per media kind.
module UploadValidation
  module_function

  # Raises ApiError::Validation with the standard {path, code, message} detail.
  # `kind` names the thing being uploaded ("Image", "Video", "Avatar") and leads
  # both messages; `formats` completes the content-type one.
  def validate!(file, path:, content_types:, max_bytes:, kind:, formats:)
    content_type = Marcel::MimeType.for(
      file.tempfile, name: file.original_filename, declared_type: file.content_type
    )

    unless content_types.include?(content_type)
      raise ApiError::Validation.for(
        path: path, code: "invalid_content_type", message: "#{kind} must be #{formats}"
      )
    end

    return unless file.size > max_bytes

    raise ApiError::Validation.for(
      path: path,
      code: "too_large",
      message: "#{kind} must be at most #{max_bytes / 1.megabyte} MB"
    )
  end
end
