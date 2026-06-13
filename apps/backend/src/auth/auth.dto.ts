import { IsJWT, IsPhoneNumber, IsString, Length } from 'class-validator';

export class SendOtpDto {
  @IsPhoneNumber('IQ')
  phone!: string;
}

export class VerifyOtpDto {
  @IsPhoneNumber('IQ')
  phone!: string;

  @IsString()
  @Length(6, 6)
  otp!: string;
}

export class RefreshDto {
  @IsJWT()
  refreshToken!: string;
}
